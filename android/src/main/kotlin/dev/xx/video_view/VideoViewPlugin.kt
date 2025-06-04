package dev.xx.video_view

import android.graphics.Color
import android.graphics.PorterDuff
import android.os.Handler
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
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry.SurfaceProducer
import kotlin.math.roundToInt

@UnstableApi
class VideoController(private val binding: FlutterPlugin.FlutterPluginBinding) : EventChannel.StreamHandler, Player.Listener, SurfaceProducer.Callback {
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

	init {
		surfaceProducer.setCallback(this)
		eventChannel.setStreamHandler(this)
		exoPlayer.addListener(this)
		exoPlayer.setVideoSurface(surfaceProducer.surface)
	}

	fun dispose() {
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
		} else if (source.startsWith("file://") || !source.contains("://")) {
			url = if (source.startsWith("file://")) source else "file://$source"
		} else {
			url = source
			networking = true
		}
		try {
			exoPlayer.setMediaItem(
				if (url.contains(".m3u8", ignoreCase = true)) MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_M3U8).build()
				else if (url.contains(".mpd", ignoreCase = true)) MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_MPD).build()
				else if (url.contains(".ism/Manifest", ignoreCase = true)) MediaItem.Builder().setUri(url).setMimeType(MimeTypes.APPLICATION_SS).build()
				else MediaItem.fromUri(url)
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
		source = null
		seeking = false
		networking = false
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
		}
		return null
	}

	fun seekTo(pos: Long, fast: Boolean): Any? {
		if (state == 1U) {
			position = pos
		} else if (exoPlayer.isCurrentMediaItemLive || exoPlayer.currentPosition == pos) {
			eventSink?.success(mapOf("event" to "seekEnd"))
		} else {
			seeking = true
			seek(pos, fast)
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
		exoPlayer.playbackParameters = exoPlayer.playbackParameters.withSpeed(speed)
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
		exoPlayer.volume = volume
		if (exoPlayer.isCurrentMediaItemLive && speed != 1F) {
			setSpeed(1F)
		}
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
		watchPosition()
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
				watchBuffer()
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
				loadEnd()
			} else {
				seekEnd()
			}
		} else if (playbackState == Player.STATE_READY) {
			if (state == 1U) {
				if (position == 0L) {
					loadEnd()
				} else {
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
			val width = (videoSize.width * videoSize.pixelWidthHeightRatio).roundToInt()
			val height = videoSize.height
			if (width > 0 && height > 0) {
				subSurfaceProducer.setSize(width, height)
			}
			eventSink?.success(mapOf(
				"event" to "videoSize",
				"width" to width.toFloat(),
				"height" to height.toFloat()
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
class VideoViewPlugin: FlutterPlugin {
	private lateinit var methodChannel: MethodChannel
	private val players = mutableMapOf<Int, VideoController>()
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
					val player = VideoController(binding)
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
					val volume = call.argument<Float>("value")
					result.success(player?.setVolume(volume!!))
				}
				"setSpeed" -> {
					val player = players[call.argument<Int>("id")!!]
					val speed = call.argument<Float>("value")
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
}