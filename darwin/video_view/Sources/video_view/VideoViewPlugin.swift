import AVFoundation
#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

class VideoControllerTexture: NSObject, FlutterTexture {
	private let callback: () -> Unmanaged<CVPixelBuffer>?
	init(cb: @escaping () -> Unmanaged<CVPixelBuffer>?) {
		callback = cb
	}
	func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
		return callback()
	}
}

class VideoController: NSObject, FlutterStreamHandler {
	var id: Int64!
	var subId: Int64!
	private let textureRegistry: FlutterTextureRegistry
	private let avPlayer = AVPlayer()
	private let subtitleLayer = AVPlayerLayer()
	private var videoTexture: VideoControllerTexture!
	private var subtitleTexture: VideoControllerTexture!
	private var eventChannel: FlutterEventChannel!
	private var videoOutput: AVPlayerItemVideoOutput?
	private var eventSink: FlutterEventSink?
	private var watcher: Any?
	private var position = CMTime.zero
	private var bufferPosition = CMTime.zero
	private var speed: Float = 1
	private var volume: Float = 1
	private var looping = false
	private var reading: CMTime?
	private var rendering: CMTime?
	private var state: UInt8 = 0 //0: idle, 1: opening, 2: ready, 3: playing
	private var orientation: UInt8 = 0
	private var source: String?
	private var mediaGroups: [AVMediaSelectionGroup] = []
	private var maxWidth = 0.0
	private var maxHeight = 0.0
	private var maxBitrate = 0.0
	private var showSubtitle = false
	private var networking = false
	private var streaming = false
	private var seeking = false

	init(registrar: FlutterPluginRegistrar) {
#if os(macOS)
		textureRegistry = registrar.textures
		let messager = registrar.messenger
#else
		textureRegistry = registrar.textures()
		let messager = registrar.messenger()
#endif
		super.init()
		videoTexture = VideoControllerTexture() { [weak self] in
			if let t = self?.reading {
				self!.reading = nil
				if let pixelBuffer = self!.videoOutput?.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
					self!.rendering = t
					return Unmanaged.passRetained(pixelBuffer)
				}
			}
			return nil
		}
		subtitleTexture = VideoControllerTexture() { [weak self] in
			if let size = self?.avPlayer.currentItem?.presentationSize,
			self!.showSubtitle {
				var subtitleBuffer: CVPixelBuffer?
				if CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, [
					kCVPixelBufferIOSurfacePropertiesKey: [:],
					kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
				] as CFDictionary, &subtitleBuffer) == kCVReturnSuccess && CVPixelBufferLockBaseAddress(subtitleBuffer!, .readOnly) == kCVReturnSuccess {
					if let context = CGContext(
						data: CVPixelBufferGetBaseAddress(subtitleBuffer!),
						width: Int(size.width),
						height: Int(size.height),
						bitsPerComponent: 8,
						bytesPerRow: CVPixelBufferGetBytesPerRow(subtitleBuffer!),
						space: CGColorSpaceCreateDeviceRGB(),
						bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue.littleEndian
					) {
#if !os(macOS)
						context.translateBy(x: 0, y: size.height)
						context.scaleBy(x: 1, y: -1)
#endif
						self!.subtitleLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
						self!.subtitleLayer.render(in: context)
					}
					CVPixelBufferUnlockBaseAddress(subtitleBuffer!, .readOnly)
					return Unmanaged.passRetained(subtitleBuffer!)
				}
			}
			return nil
		}
		id = textureRegistry.register(videoTexture)
		subId = textureRegistry.register(subtitleTexture)
		eventChannel = FlutterEventChannel(name: "VideoViewPlugin/\(id!)", binaryMessenger: messager)
		eventChannel.setStreamHandler(self)
		setKeepScreenOn(enable: false)
		avPlayer.appliesMediaSelectionCriteriaAutomatically = true
		setPreferredAudioLanguage(language: "")
		setPreferredSubtitleLanguage(language: "")
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options: .old, context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status), context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.loadedTimeRanges), context: nil)
		avPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.presentationSize), context: nil)
		subtitleLayer.player = avPlayer
	}

	deinit {
		eventSink?(FlutterEndOfEventStream)
		eventChannel.setStreamHandler(nil)
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.status))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.loadedTimeRanges))
		avPlayer.removeObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.presentationSize))
		textureRegistry.unregisterTexture(id)
		subtitleLayer.player = nil
	}

	func open(source: String) {
		close()
		let uri: URL?
		if source.starts(with: "asset://") {
			uri = URL(fileURLWithPath: Bundle.main.bundlePath + "/" + FlutterDartProject.lookupKey(forAsset: String(source.suffix(source.count - 8))))
		} else if source.contains("://") {
			uri = URL(string: source)
		} else {
			uri = URL(fileURLWithPath: source)
		}
		if uri == nil {
			eventSink?([
				"event": "error",
				"value": "Invalid source"
			])
		} else {
			networking = !uri!.isFileURL
			self.source = source
			state = 1
			avPlayer.replaceCurrentItem(with: AVPlayerItem(asset: AVAsset(url: uri!)))
			//AVPlayer.eligibleForHDRPlayback
			//avPlayer.currentItem!.appliesPerFrameHDRDisplayMetadata = true
			avPlayer.currentItem!.preferredPeakBitRate = maxBitrate
			avPlayer.currentItem!.preferredMaximumResolution = maxWidth == 0 && maxHeight == 0 ? CGSizeZero : CGSize(width: maxWidth, height: maxHeight)
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(onFinish(notification:)),
				name: AVPlayerItem.didPlayToEndTimeNotification,
				object: avPlayer.currentItem
			)
		}
	}

	func close() {
		state = 0
		orientation = 0
		position = .zero
		bufferPosition = .zero
		avPlayer.pause()
		stopVideo()
		stopWatcher()
		source = nil
		reading = nil
		rendering = nil
		networking = false
		streaming = false
		seeking = false
		mediaGroups.removeAll()
		if avPlayer.currentItem != nil {
			NotificationCenter.default.removeObserver(
				self,
				name: AVPlayerItem.didPlayToEndTimeNotification,
				object: avPlayer.currentItem
			)
			avPlayer.replaceCurrentItem(with: nil)
		}
	}

	func play() {
		if state == 2 {
			state = 3
			justPlay()
		}
	}

	func pause() {
		if state > 2 {
			state = 2
			avPlayer.pause()
		}
	}

	func seekTo(pos: Int64, fast: Bool) {
		let time = CMTime(seconds: Double(pos) / 1000, preferredTimescale: 1000)
		if state == 1 {
			if seeking {
				startAt(time: time)
			} else {
				position = time
			}
		} else if state > 1 {
			if avPlayer.currentTime() != time {
				seeking = true
				seek(to: time, fast: fast) { [weak self] finished in
					if finished && self != nil {
						self!.seeking = false
						self!.eventSink?(["event": "seekEnd"])
						if self!.watcher == nil {
							self!.setPosition(time: self!.avPlayer.currentTime())
						}
					}
				}
			} else if !seeking {
				eventSink?(["event": "seekEnd"])
			}
		}
	}

	func setVolume(vol: Float) {
		volume = vol
		avPlayer.volume = volume
	}

	func setSpeed(spd: Float) {
		speed = spd
		if !streaming && avPlayer.rate > 0 {
			avPlayer.rate = speed
		}
	}

	func setLooping(loop: Bool) {
		looping = loop
	}

	func setMaxBitRate(bitrate: Int64) {
		maxBitrate = Double(bitrate)
		if state > 0 {
			avPlayer.currentItem!.preferredPeakBitRate = maxBitrate
		}
	}

	func setMaxResolution(width: Double, height: Double) {
		maxWidth = width
		maxHeight = height
		if state > 0 {
			avPlayer.currentItem!.preferredMaximumResolution = maxWidth == 0 && maxHeight == 0 ? CGSizeZero : CGSize(width: maxWidth, height: maxHeight)
		}
	}

	func setPreferredAudioLanguage(language: String) {
		avPlayer.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(
			preferredLanguages: language.isEmpty ? Locale.preferredLanguages : [language],
			preferredMediaCharacteristics: nil
		), forMediaCharacteristic: AVMediaCharacteristic.audible)
	}

	func setPreferredSubtitleLanguage(language: String) {
		avPlayer.setMediaSelectionCriteria(AVPlayerMediaSelectionCriteria(
			preferredLanguages: language.isEmpty ? Locale.preferredLanguages : [language],
			preferredMediaCharacteristics: nil
		), forMediaCharacteristic: AVMediaCharacteristic.legible)
	}

	func setShowSubtitle(show: Bool) {
		showSubtitle = show
		if showSubtitle && state == 2 {
			textureRegistry.textureFrameAvailable(subId)
		}
	}
	
	func setKeepScreenOn(enable: Bool) {
		avPlayer.preventsDisplaySleepDuringVideoPlayback = enable
	}

	func overrideTrack(groupId: Int, trackId: Int, enabled: Bool) {
		if state > 1 {
			let group = mediaGroups[groupId]
			let option = group.options[trackId]
			if enabled {
				avPlayer.currentItem!.select(option, in: group)
			} else if avPlayer.currentItem!.currentMediaSelection.selectedMediaOption(in: group) == option {
				avPlayer.currentItem!.selectMediaOptionAutomatically(in: group)
			}
		}
	}
	
	private func seek(to: CMTime, fast: Bool, completion: @escaping (Bool) -> Void) {
		if fast {
			avPlayer.seek(to: to, completionHandler: completion)
		} else {
			avPlayer.seek(to: to, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)
		}
	}
	
	private func startAt(time: CMTime) {
		seek(to: time, fast: true) { [weak self] finished in
			if finished && self != nil {
				self!.seeking = false
				self!.loadEnd()
			}
		}
	}

	private func justPlay() {
		if streaming {
			avPlayer.rate = 1
		} else if position == avPlayer.currentItem!.duration {
			avPlayer.seek(to: .zero) { [weak self] finished in
				if finished && self != nil {
					self!.setPosition(time: .zero)
					self!.justPlay()
				}
			}
		} else {
			if watcher == nil && avPlayer.currentItem != nil {
				watcher = avPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.01, preferredTimescale: 1000), queue: nil) { [weak self] time in
					if self != nil {
						if self!.avPlayer.rate == 0 || self!.avPlayer.error != nil {
							self!.stopWatcher()
						}
						self!.setPosition(time: time)
					}
				}
			}
			avPlayer.rate = speed
		}
	}

	private func createOutput() {
		let ioSurfaceProps: [String: Any] = [:]
		let attributes: [String: Any] = [
			String(kCVPixelBufferIOSurfacePropertiesKey): ioSurfaceProps,
			String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
		]
		videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
		avPlayer.currentItem!.add(videoOutput!)
	}

	private func stopVideo() {
		if displayLink != nil {
#if os(macOS)
			CVDisplayLinkStop(displayLink!)
#else
			displayLink!.invalidate()
#endif
			displayLink = nil
		}
		if videoOutput != nil {
			avPlayer.currentItem?.remove(videoOutput!)
			videoOutput = nil
		}
	}

	private func stopWatcher() {
		if watcher != nil {
			avPlayer.removeTimeObserver(watcher!)
			watcher = nil
		}
	}

	private func safeTimeToMilliseconds(_ time: CMTime) -> Int {
		let seconds = time.seconds
		if seconds.isInfinite || seconds.isNaN {
			return 0
		}
		let milliseconds = seconds * 1000
		if milliseconds > Double(Int.max) {
			return Int.max
		}
		if milliseconds < Double(Int.min) {
			return Int.min
		}
		return Int(milliseconds)
	}

	private func setPosition(time: CMTime) {
		if time != position {
			position = time
			eventSink?([
				"event": "position",
				"value": safeTimeToMilliseconds(position)
			])
		}
	}

	private func sendBuffer(currentTime: CMTime) {
		eventSink?([
			"event": "buffer",
			"start": safeTimeToMilliseconds(currentTime),
			"end": safeTimeToMilliseconds(bufferPosition)
		])
	}
	
	private func loadEnd() {
		Task { @MainActor in
			if state == 1 && avPlayer.currentItem?.status == .readyToPlay {
				let audioTracks = NSMutableDictionary()
				let subtitleTracks = NSMutableDictionary()
				if let characteristics = try? await avPlayer.currentItem!.asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions) {
					for characteristic in characteristics {
						if let group = try? await avPlayer.currentItem!.asset.loadMediaSelectionGroup(for: characteristic) {
							let i = mediaGroups.count
							for j in 0..<group.options.count {
								if group.options[j].isPlayable {
									let tracks: NSMutableDictionary? = if group.options[j].mediaType == .audio {
										audioTracks
									} else if group.options[j].mediaType == .subtitle || group.options[j].mediaType == .closedCaption || group.options[j].mediaType == .text {
										subtitleTracks
									} else {
										nil
									}
									if tracks != nil {
										if mediaGroups.count == i {
											mediaGroups.append(group)
										}
										tracks!["\(i).\(j)"] = [
											"title": group.options[j].displayName,
											"language": group.options[j].locale?.identifier ?? group.options[j].extendedLanguageTag
										]
									}
								}
							}
						}
					}
				}
				if let videos = try? await avPlayer.currentItem!.asset.loadTracks(withMediaType: .video) {
					if let transform = videos.first?.preferredTransform {
					 	switch (transform.a, transform.b, transform.c, transform.d) {
					 	case (0, 1, -1, 0):
						 	orientation = 1
				 	 	case (-1, 0, 0, -1):
				 		 	orientation = 2
				 	 	case (0, -1, 1, 0):
					 	 	orientation = 3
					 	case (-1, 0, 0, 1):
						 	orientation = 4
					 	case (0, 1, 1, 0):
						 	orientation = 5
					 	case (1, 0, 0, -1):
						 	orientation = 6
					 	case (0, -1, -1, 0):
						 	orientation = 7
					 	default:
						 	break
					 	}
				 	}
				}
				avPlayer.volume = volume
				state = 2
				eventSink?([
					"event": "mediaInfo",
					"duration": streaming ? 0 : safeTimeToMilliseconds(avPlayer.currentItem!.duration),
					"audioTracks": audioTracks,
					"subtitleTracks": subtitleTracks,
					"source": source!
				])
				if !streaming {
					let time = avPlayer.currentTime()
					if time != .zero {
						setPosition(time: time)
					}
					if networking && bufferPosition > time {
						sendBuffer(currentTime: time)
					}
				}
			}
		}
	}

	@objc
	private func onFinish(notification: NSNotification) {
		if state > 2 {
			if streaming {
				close()
			} else {
				if watcher != nil {
					stopWatcher()
				}
				setPosition(time: avPlayer.currentItem!.duration)
				if looping {
					justPlay()
				} else {
					state = 2
				}
			}
			eventSink?(["event": "finished"])
		}
	}

	func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
		eventSink = events
		return nil
	}

	func onCancel(withArguments arguments: Any?) -> FlutterError? {
		eventSink = nil
		return nil
	}

#if os(macOS)
	private var displayLink: CVDisplayLink?
	private func displayCallback(outputTime: CVTimeStamp) {
		if let t = videoOutput?.itemTime(for: outputTime),
		reading != t && rendering != t {
			textureRegistry.textureFrameAvailable(id)
			if showSubtitle {
				textureRegistry.textureFrameAvailable(subId)
			}
			reading = t
		}
	}
#else
	private var displayLink: CADisplayLink?
	@objc
	private func displayCallback() {
		if let t = videoOutput?.itemTime(forHostTime: displayLink!.targetTimestamp),
		reading != t && rendering != t {
			textureRegistry.textureFrameAvailable(id)
			if showSubtitle {
				textureRegistry.textureFrameAvailable(subId)
			}
			reading = t
		}
	}
#endif

	override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		switch keyPath {
		case #keyPath(AVPlayer.timeControlStatus):
			if let oldValue = change?[NSKeyValueChangeKey.oldKey] as? Int,
			let oldStatus = AVPlayer.TimeControlStatus(rawValue: oldValue),
			state > 2 && (oldStatus == .waitingToPlayAtSpecifiedRate || avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate) {
				eventSink?([
					"event": "loading",
					"value": avPlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
				])
			}
		case #keyPath(AVPlayer.currentItem.status):
			switch avPlayer.currentItem?.status {
			case .readyToPlay:
				if state == 1 {
					streaming = safeTimeToMilliseconds(avPlayer.currentItem!.duration) <= 0
					if streaming || position == .zero {
						position = .zero
						loadEnd()
					} else {
						seeking = true
						startAt(time: position)
						position = .zero
					}
				}
			case .failed:
				if state > 0 {
					eventSink?([
						"event": "error",
						"value": avPlayer.currentItem?.error?.localizedDescription ?? "Unknown error"
					])
					close()
				}
			default:
				break
			}
		case #keyPath(AVPlayer.currentItem.presentationSize):
			if state > 0,
			let width = avPlayer.currentItem?.presentationSize.width,
			let height = avPlayer.currentItem?.presentationSize.height {
				if width == 0 || height == 0 {
					stopVideo()
				} else if displayLink == nil {
#if os(macOS)
					CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
					if displayLink != nil {
						CVDisplayLinkSetOutputCallback(displayLink!, { (displayLink, now, outputTime, flagsIn, flagsOut, context) -> CVReturn in
							let player: VideoController = Unmanaged.fromOpaque(context!).takeUnretainedValue()
							player.displayCallback(outputTime: outputTime.pointee)
							return kCVReturnSuccess
						}, Unmanaged.passUnretained(self).toOpaque())
						CVDisplayLinkStart(displayLink!)
						createOutput()
					}
#else
					displayLink = CADisplayLink(target: self, selector: #selector(displayCallback))
					displayLink!.add(to: .current, forMode: .common)
					createOutput()
#endif
				}
				eventSink?([
					"event": "videoSize",
					"orientation": orientation,
					"width": width,
					"height": height
				])
			}
		case #keyPath(AVPlayer.currentItem.loadedTimeRanges):
			if networking && !streaming,
			let currentTime = avPlayer.currentItem?.currentTime(),
			let timeRanges = avPlayer.currentItem?.loadedTimeRanges as? [CMTimeRange] {
				for timeRange in timeRanges {
					let end = timeRange.start + timeRange.duration
					if timeRange.start <= currentTime && end >= currentTime {
						if end != bufferPosition {
							bufferPosition = end
							if state > 1 {
								sendBuffer(currentTime: currentTime)
							}
						}
						break
					}
				}
			}
		default:
			break
		}
	}
}

public class VideoViewPlugin: NSObject, FlutterPlugin {
	public static func register(with registrar: FlutterPluginRegistrar) {
#if os(macOS)
		let messager = registrar.messenger
#else
		let messager = registrar.messenger()
#endif
		registrar.addMethodCallDelegate(
			VideoViewPlugin(registrar: registrar),
			channel: FlutterMethodChannel(name: "VideoViewPlugin", binaryMessenger: messager)
		)
	}

	private var players: [Int64: VideoController] = [:]
	private let registrar: FlutterPluginRegistrar

	init(registrar: FlutterPluginRegistrar) {
		self.registrar = registrar
		super.init()
	}

	public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
		for player in players.values {
			player.close()
		}
		players.removeAll()
	}

	public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
		var response: Any?
		switch call.method {
		case "create":
			let player = VideoController(registrar: registrar)
			players[player.id] = player
			response = [
				"id": player.id,
				"subId": player.subId
			]
		case "dispose":
			if let id = call.arguments as? Int64 {
				players[id]?.close()
				players.removeValue(forKey: id)
			} else {
				detachFromEngine(for: registrar)
			}
		case "close":
			let player = players[call.arguments as! Int64]
			player?.close()
		case "play":
			let player = players[call.arguments as! Int64]
			player?.play()
		case "pause":
			let player = players[call.arguments as! Int64]
			player?.pause()
		case "open":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let src = args["value"] as! String
			player?.open(source: src)
		case "seekTo":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let pos = args["position"] as? Int64
			let fast = args["fast"] as? Bool
			player?.seekTo(pos: pos!, fast: fast!)
		case "setVolume":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let vol = args["value"] as? Double
			player?.setVolume(vol: Float(vol!))
		case "setSpeed":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let spd = args["value"] as? Double
			player?.setSpeed(spd: Float(spd!))
		case "setLooping":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let loop = args["value"] as? Bool
			player?.setLooping(loop: loop!)
		case "setMaxBitRate":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let bitrate = args["value"] as? Int64
			player?.setMaxBitRate(bitrate: bitrate!)
		case "setMaxResolution":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let width = args["width"] as? Double
			let height = args["height"] as? Double
			player?.setMaxResolution(width: width!, height: height!)
		case "setPreferredAudioLanguage":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let language = args["value"] as? String
			player?.setPreferredAudioLanguage(language: language!)
		case "setPreferredSubtitleLanguage":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let language = args["value"] as? String
			player?.setPreferredSubtitleLanguage(language: language!)
		case "setShowSubtitle":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let show = args["value"] as? Bool
			player?.setShowSubtitle(show: show!)
		case "setKeepScreenOn":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let keepOn = args["value"] as? Bool
			player?.setKeepScreenOn(enable: keepOn!)
		case "overrideTrack":
			let args = call.arguments as! [String: Any]
			let player = players[args["id"] as! Int64]
			let groupId = args["groupId"] as? Int
			let trackId = args["trackId"] as? Int
			let enabled = args["enabled"] as? Bool
			player?.overrideTrack(groupId: groupId!, trackId: trackId!, enabled: enabled!)
		default:
			response = FlutterMethodNotImplemented
		}
		result(response)
	}
}
