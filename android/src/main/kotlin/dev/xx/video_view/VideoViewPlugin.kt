package dev.xx.video_view

import android.app.Activity
import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
import android.view.WindowManager.LayoutParams
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry.SurfaceProducer
import kotlin.math.roundToInt

@UnstableApi
class VideoController(
	private val binding: FlutterPlugin.FlutterPluginBinding,
	private val plugin: VideoViewPlugin
) : EventChannel.StreamHandler, Player.Listener, SurfaceProducer.Callback {
	private val surfaceProducer = binding.textureRegistry.createSurfaceProducer()
	private val subSurfaceProducer = binding.textureRegistry.createSurfaceProducer()
	val id = surfaceProducer.id().toInt()
	val subId = subSurfaceProducer.id().toInt()
	private val exoPlayer = ExoPlayer.Builder(binding.applicationContext).build()
	private val handler = Handler(exoPlayer.applicationLooper)
	private val eventChannel = EventChannel(binding.binaryMessenger, "VideoViewPlugin/$id")
	private val subtitlePainter = SubtitlePainter(binding.applicationContext)
	private var speed = 1F
	private var volume = 1F
	private var looping = false
	private var position = 0L
	private var eventSink: EventChannel.EventSink? = null
	private var watching = false
	private var buffering = false
	private var bufferPosition = 0L
	private var state = 0U // 0: idle, 1: opening, 2: ready, 3: playing
	private var source: String? = null
	private var seeking = false
	private var networking = false
	private var showSubtitle = false
	private var keepScreenOn = false
	private var hasVideo = false

	init {
		surfaceProducer.setCallback(this)
		eventChannel.setStreamHandler(this)
		exoPlayer.addListener(this)
		exoPlayer.setVideoSurface(surfaceProducer.surface)
	}

	fun dispose() {
		plugin.requestKeepScreenOn(id, false)
		eventChannel.setStreamHandler(null)
		handler.removeCallbacksAndMessages(null)
		exoPlayer.release()
		surfaceProducer.release()
		subSurfaceProducer.release()
		eventSink?.endOfStream()
	}

	fun open(source: String): Any? {
		close()
		val url: String
		if (source.startsWith("asset://")) {
			url = "asset:///${binding.flutterAssets.getAssetFilePathBySubpath(source.substring(8))}"
		} else if (!source.contains("://")) {
			url = "file://$source"
		} else {
			url = source
			networking = !source.startsWith("file://")
		}
		val match = Regex("\\.(?:mpd|ism/manifest|m3u8)", RegexOption.IGNORE_CASE).findAll(url)
		val ext = if (match.any()) match.last().value.lowercase() else ""
		try {
			exoPlayer.setMediaItem(
				when (ext) {
					".m3u8" -> MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_M3U8).build()
					".mpd" -> MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_MPD).build()
					".ism/manifest" -> MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_SS).build()
					else -> MediaItem.fromUri(url)
				}
			)
			exoPlayer.prepare()
			state = 1U
			this.source = source
		} catch (e: Exception) {
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to e.toString()
			))
		}
		return null
	}

	fun close(): Any? {
		plugin.requestKeepScreenOn(id, false)
		source = null
		seeking = false
		networking = false
		hasVideo = false
		state = 0U
		position = 0
		bufferPosition = 0
		exoPlayer.playWhenReady = false
		exoPlayer.stop()
		exoPlayer.clearMediaItems()
		clearSubtitle()
		if (exoPlayer.trackSelectionParameters.overrides.isNotEmpty()) {
			exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().clearOverrides().build()
		}
		return null
	}

	fun play(): Any? {
		if (state == 2U) {
			state = 3U
			justPlay()
			if (hasVideo && keepScreenOn) {
				plugin.requestKeepScreenOn(id, true)
			}
			if (exoPlayer.playbackState == Player.STATE_BUFFERING) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to true
				))
			}
		}
		return null
	}

	fun pause(): Any? {
		if (state > 2U) {
			state = 2U
			exoPlayer.playWhenReady = false
			plugin.requestKeepScreenOn(id, false)
		}
		return null
	}

	fun seekTo(pos: Long, fast: Boolean): Any? {
		if (state == 1U) {
			if (seeking) {
				seek(pos, true)
			} else {
				position = pos
			}
		} else if (state > 1U) {
			if (exoPlayer.currentPosition != pos) {
				seeking = true
				seek(pos, fast)
			} else if (!seeking) {
				eventSink?.success(mapOf("event" to "seekEnd"))
			}
		}
		return null
	}

	fun setVolume(vol: Float): Any? {
		volume = vol
		exoPlayer.volume = vol
		return null
	}

	fun setSpeed(spd: Float): Any? {
		speed = spd
		if (!exoPlayer.isCurrentMediaItemLive) {
			justSetSpeed(speed)
		}
		return null
	}

	fun setLooping(loop: Boolean): Any? {
		looping = loop
		return null
	}

	fun setMaxResolution(width: Double, height: Double): Any? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setMaxVideoSize(width.toInt(), height.toInt()).build()
		return null
	}

	fun setMaxBitrate(bitrate: Int): Any? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setMaxVideoBitrate(bitrate).build()
		return null
	}

	fun setPreferredAudioLanguage(language: String): Any? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setPreferredAudioLanguage(language.ifEmpty { null }).build()
		return null
	}

	fun setPreferredSubtitleLanguage(language: String): Any? {
		exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setPreferredTextLanguage(language.ifEmpty { null }).build()
		return null
	}

	fun setShowSubtitle(show: Boolean): Any? {
		showSubtitle = show
		if (showSubtitle) {
			clearSubtitle()
		}
		return null
	}

	fun setKeepScreenOn(enable: Boolean): Any? {
		if (keepScreenOn != enable) {
			keepScreenOn = enable
			if (state > 2U && hasVideo) {
				plugin.requestKeepScreenOn(id, enable)
			}
		}
		return null
	}

	fun overrideTrack(groupId: Int, trackId: Int, enabled: Boolean): Any? {
		if (state > 1U) {
			val group = exoPlayer.currentTracks.groups[groupId]
			if (group != null && (group.type == C.TRACK_TYPE_AUDIO || group.type == C.TRACK_TYPE_TEXT) && group.isTrackSupported(trackId, false)) {
				if (enabled) {
					exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackId)).build()
				} else if (exoPlayer.trackSelectionParameters.overrides.contains(group.mediaTrackGroup) && exoPlayer.trackSelectionParameters.overrides[group.mediaTrackGroup]!!.trackIndices.contains(trackId)) {
					exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters.buildUpon().clearOverride(group.mediaTrackGroup).build()
				}
			}
		}
		return null
	}

	private fun clearSubtitle() {
		val canvas = subSurfaceProducer.surface.lockHardwareCanvas()
		canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
		subSurfaceProducer.surface.unlockCanvasAndPost(canvas)
	}

	private fun seek(pos: Long, fast: Boolean) {
		exoPlayer.setSeekParameters(if (fast) SeekParameters.CLOSEST_SYNC else SeekParameters.EXACT)
		exoPlayer.seekTo(pos)
	}

	private fun seekEnd() {
		seeking = false
		if (!watching) {
			watchPosition()
		}
		eventSink?.success(mapOf("event" to "seekEnd"))
	}

	private fun loadEnd() {
		state = 2U
		val audioTracks = mutableMapOf<String, MutableMap<String, Any?>>()
		val subtitleTracks = mutableMapOf<String, MutableMap<String, Any?>>()
		for (i in 0 until exoPlayer.currentTracks.groups.size) {
			val group = exoPlayer.currentTracks.groups[i]
			if (group.type == C.TRACK_TYPE_AUDIO || group.type == C.TRACK_TYPE_TEXT) {
				for (j in 0 until group.length) {
					if (group.isTrackSupported(j, false)) {
						val format = group.getTrackFormat(j)
						if (format.roleFlags != C.ROLE_FLAG_TRICK_PLAY) {
							val track = mutableMapOf<String, Any?>(
								"title" to format.label,
								"language" to format.language,
								"format" to if (format.codecs == null) format.sampleMimeType else format.codecs
							)
							if (group.type == C.TRACK_TYPE_AUDIO) {
								track["channels"] = format.channelCount
								track["sampleRate"] = format.sampleRate
								track["bitRate"] = if (format.averageBitrate > 0) format.averageBitrate else format.bitrate
								audioTracks["$i.$j"] = track
							} else {
								subtitleTracks["$i.$j"] = track
							}
						}
					}
				}
			}
		}
		eventSink?.success(mapOf(
			"event" to "mediaInfo",
			"duration" to if (exoPlayer.isCurrentMediaItemLive) 0 else exoPlayer.duration,
			"audioTracks" to audioTracks,
			"subtitleTracks" to subtitleTracks,
			"source" to source
		))
		if (!exoPlayer.isCurrentMediaItemLive) {
			watchPosition()
			if (networking) {
				watchBuffer()
			}
		}
	}

	private fun justSetSpeed(spd: Float) {
		exoPlayer.playbackParameters = exoPlayer.playbackParameters.withSpeed(spd)
	}

	private fun justPlay() {
		if (exoPlayer.playbackState == Player.STATE_ENDED) {
			seek(0, true)
		}
		exoPlayer.playWhenReady = true
		if (!watching && !exoPlayer.isCurrentMediaItemLive) {
			startWatcher()
		}
	}

	private fun startBuffering() {
		buffering = true
		handler.postDelayed({
			if (state > 0U && networking && exoPlayer.isLoading && !exoPlayer.isCurrentMediaItemLive) {
				startBuffering()
				if (state > 1U) {
					watchBuffer()
				}
			} else {
				buffering = false
			}
		}, 100)
	}

	private fun watchBuffer() {
		val bufferPos = exoPlayer.bufferedPosition
		if (bufferPos != bufferPosition && bufferPos > exoPlayer.currentPosition) {
			bufferPosition = bufferPos
			eventSink?.success(mapOf(
				"event" to "buffer",
				"start" to exoPlayer.currentPosition,
				"end" to bufferPosition
			))
		}
	}

	private fun startWatcher() {
		watching = true
		handler.postDelayed({
			if (state > 2U && !exoPlayer.isCurrentMediaItemLive) {
				startWatcher()
			} else {
				watching = false
			}
			watchPosition()
		}, 10)
	}

	private fun watchPosition() {
		val pos = exoPlayer.currentPosition
		if (pos != position) {
			position = pos
			eventSink?.success(mapOf(
				"event" to "position",
				"value" to pos
			))
		}
	}

	override fun onPlayerError(error: PlaybackException) {
		super.onPlayerError(error)
		if (state > 0U) {
			close()
			eventSink?.success(mapOf(
				"event" to "error",
				"value" to error.errorCodeName
			))
		}
	}

	override fun onPlaybackStateChanged(playbackState: Int) {
		super.onPlaybackStateChanged(playbackState)
		if (seeking && (playbackState == Player.STATE_READY || playbackState == Player.STATE_ENDED)) {
			if (state == 1U) {
				seeking = false
				loadEnd()
			} else {
				seekEnd()
			}
		} else if (playbackState == Player.STATE_READY) {
			if (state == 1U) {
				exoPlayer.volume = volume
				justSetSpeed(if (exoPlayer.isCurrentMediaItemLive) 1F else speed)
				if (exoPlayer.isCurrentMediaItemLive || position == 0L) {
					position = 0L
					loadEnd()
				} else {
					seeking = true
					seek(position, true)
					position = 0L
				}
			} else if (state > 2U) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to false
				))
			}
		} else if (playbackState == Player.STATE_ENDED) {
			if (state > 1U && !exoPlayer.isCurrentMediaItemLive) {
				eventSink?.success(mapOf(
					"event" to "position",
					"value" to exoPlayer.duration
				))
			}
			if (state > 2U) {
				if (exoPlayer.isCurrentMediaItemLive) {
					close()
				} else if (looping) {
					justPlay()
				} else {
					state = 2U
					plugin.requestKeepScreenOn(id, false)
				}
				eventSink?.success(mapOf("event" to "finished"))
			}
		} else if (playbackState == Player.STATE_BUFFERING) {
			if (state > 2U) {
				eventSink?.success(mapOf(
					"event" to "loading",
					"value" to true
				))
			}
		}
	}

	override fun onIsLoadingChanged(isLoading: Boolean) {
		super.onIsLoadingChanged(isLoading)
		if (networking && !exoPlayer.isCurrentMediaItemLive) {
			if (isLoading) {
				if (!buffering) {
					startBuffering()
				}
			} else if (buffering) {
				buffering = false
				watchBuffer()
			}
		}
	}

	override fun onVideoSizeChanged(videoSize: VideoSize) {
		super.onVideoSizeChanged(videoSize)
		if (state > 0U) {
			// Get rotation from video format metadata
			val videoFormat = exoPlayer.videoFormat
			val rotationDegrees = videoFormat?.rotationDegrees ?: 0

			// Calculate dimensions with pixel aspect ratio
			// Note: We don't swap width/height here - RotatedBox in Flutter handles that
			val width = (videoSize.width * videoSize.pixelWidthHeightRatio).roundToInt()
			val height = videoSize.height

			val newHasVideo = width > 0 && height > 0
			if (newHasVideo != hasVideo) {
				hasVideo = newHasVideo
				if (state > 2U && keepScreenOn) {
					plugin.requestKeepScreenOn(id, hasVideo)
				}
			}
			if (hasVideo) {
				subSurfaceProducer.setSize(width, height)
			}
			eventSink?.success(mapOf(
				"event" to "videoSize",
				"width" to width.toFloat(),
				"height" to height.toFloat(),
				"rotation" to rotationDegrees
			))
		}
	}

	override fun onCues(cueGroup: CueGroup) {
		super.onCues(cueGroup)
		if (state > 0U && showSubtitle) {
			val canvas = subSurfaceProducer.surface.lockHardwareCanvas()
			canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
			for (cue in cueGroup.cues) {
				subtitlePainter.draw(cue, canvas)
			}
			subSurfaceProducer.surface.unlockCanvasAndPost(canvas)
		}
	}

	override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
		eventSink = events
	}

	override fun onCancel(arguments: Any?) {
		eventSink = null
	}

	override fun onSurfaceAvailable() {
		exoPlayer.setVideoSurface(surfaceProducer.surface)
	}

	override fun onSurfaceCleanup() {
		exoPlayer.setVideoSurface(null)
	}
}

@UnstableApi
class VideoViewPlugin : FlutterPlugin, ActivityAware {
	private lateinit var methodChannel: MethodChannel
	private val players = mutableMapOf<Int, VideoController>()
	private val keepScreenOnRefs = mutableSetOf<Int>()
	private var activity: Activity? = null

	fun requestKeepScreenOn(id: Int, enable: Boolean) {
		if (enable) {
			keepScreenOnRefs.add(id)
			activity?.window?.addFlags(LayoutParams.FLAG_KEEP_SCREEN_ON)
		} else if (keepScreenOnRefs.remove(id) && keepScreenOnRefs.isEmpty()) {
			activity?.window?.clearFlags(LayoutParams.FLAG_KEEP_SCREEN_ON)
		}
	}

	private fun clear() {
		for (player in players.values) {
			player.dispose()
		}
		players.clear()
	}

	override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel = MethodChannel(binding.binaryMessenger, "VideoViewPlugin")
		methodChannel.setMethodCallHandler { call, result ->
			when (call.method) {
				"create" -> {
					val player = VideoController(binding, this)
					players[player.id] = player
					result.success(mapOf(
						"id" to player.id,
						"subId" to player.subId
					))
				}
				"dispose" -> {
					val id = call.arguments
					if (id is Int) {
						players[id]?.dispose()
						players.remove(id)
					} else {
						clear()
					}
					result.success(null)
				}
				"close" -> {
					val player = players[call.arguments as Int]
					result.success(player?.close())
				}
				"play" -> {
					val player = players[call.arguments as Int]
					result.success(player?.play())
				}
				"pause" -> {
					val player = players[call.arguments as Int]
					result.success(player?.pause())
				}
				"open" -> {
					val player = players[call.argument<Int>("id")!!]
					val source = call.argument<String>("value")
					result.success(player?.open(source!!))
				}
				"seekTo" -> {
					val player = players[call.argument<Int>("id")!!]
					val position = call.argument<Int>("position")
					val fast = call.argument<Boolean>("fast")
					result.success(player?.seekTo(position!!.toLong(), fast!!))
				}
				"setVolume" -> {
					val player = players[call.argument<Int>("id")!!]
					val volume = call.argument<Double>("value")?.toFloat()
					result.success(player?.setVolume(volume!!))
				}
				"setSpeed" -> {
					val player = players[call.argument<Int>("id")!!]
					val speed = call.argument<Double>("value")?.toFloat()
					result.success(player?.setSpeed(speed!!))
				}
				"setLooping" -> {
					val player = players[call.argument<Int>("id")!!]
					val looping = call.argument<Boolean>("value")
					result.success(player?.setLooping(looping!!))
				}
				"setMaxResolution" -> {
					val player = players[call.argument<Int>("id")!!]
					val width = call.argument<Double>("width")
					val height = call.argument<Double>("height")
					result.success(player?.setMaxResolution(width!!, height!!))
				}
				"setMaxBitrate" -> {
					val player = players[call.argument<Int>("id")!!]
					val bitrate = call.argument<Int>("value")
					result.success(player?.setMaxBitrate(bitrate!!))
				}
				"setPreferredAudioLanguage" -> {
					val player = players[call.argument<Int>("id")!!]
					val language = call.argument<String>("value")
					result.success(player?.setPreferredAudioLanguage(language!!))
				}
				"setPreferredSubtitleLanguage" -> {
					val player = players[call.argument<Int>("id")!!]
					val language = call.argument<String>("value")
					result.success(player?.setPreferredSubtitleLanguage(language!!))
				}
				"setShowSubtitle" -> {
					val player = players[call.argument<Int>("id")!!]
					val show = call.argument<Boolean>("value")
					result.success(player?.setShowSubtitle(show!!))
				}
				"setKeepScreenOn" -> {
					val player = players[call.argument<Int>("id")!!]
					val enable = call.argument<Boolean>("value")
					result.success(player?.setKeepScreenOn(enable!!))
				}
				"overrideTrack" -> {
					val player = players[call.argument<Int>("id")!!]
					val groupId = call.argument<Int>("groupId")
					val trackId = call.argument<Int>("trackId")
					val enabled = call.argument<Boolean>("enabled")
					result.success(player?.overrideTrack(groupId!!, trackId!!, enabled!!))
				}
				else -> {
					result.notImplemented()
				}
			}
		}
	}

	override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		methodChannel.setMethodCallHandler(null)
		clear()
	}

	override fun onAttachedToActivity(binding: ActivityPluginBinding) {
		activity = binding.activity
		if (keepScreenOnRefs.isNotEmpty()) {
			activity!!.window?.addFlags(LayoutParams.FLAG_KEEP_SCREEN_ON)
		}
	}

	override fun onDetachedFromActivity() {
		if (keepScreenOnRefs.isNotEmpty()) {
			activity?.window?.clearFlags(LayoutParams.FLAG_KEEP_SCREEN_ON)
		}
		activity = null
	}

	override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
		onAttachedToActivity(binding)
	}

	override fun onDetachedFromActivityForConfigChanges() {
		onDetachedFromActivity()
	}
}