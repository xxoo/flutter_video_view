#include "include/video_view/video_view_plugin_c_api.h"
#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <d3d11.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.core.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.System.UserProfile.h>
#include <DispatcherQueue.h>
#include <mutex>

#undef max //we want to use std::max

using namespace std;
using namespace flutter;
using namespace winrt;
using namespace winrt::Windows::System;
using namespace winrt::Windows::System::UserProfile;
using namespace winrt::Windows::Media::Core;
using namespace winrt::Windows::Media::Playback;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

class VideoController : public enable_shared_from_this<VideoController> {
	static ID3D11Device* d3dDevice;
	static ID3D11DeviceContext* d3dContext;
	static DispatcherQueueController dispatcherController;
	static DispatcherQueue dispatcherQueue;

	static char lower(const char c) {
		return c >= 'A' && c <= 'Z' ? c + 32 : c;
	}

	static void split(const string& input, const char delimiter, vector<string>& tokens) {
		string_view input_view{ input };
		size_t start = 0;
		auto end = input_view.find(delimiter);
		while (end != string_view::npos) {
			tokens.push_back(string(input_view.substr(start, end - start)));
			start = end + 1;
			end = input_view.find(delimiter, start);
		}
		tokens.push_back(string(input_view.substr(start)));
	}

	static int16_t getBestMatch(const map<uint16_t, vector<string>>& lang) {
		if (lang.size() == 0) {
			return -1;
		} else if (lang.size() == 1) {
			return lang.begin()->first;
		} else {
			uint8_t count = 3;
			int16_t j = 0;
			for (auto& [i, t] : lang) {
				if (t.size() < count) {
					j = i;
					count = (uint8_t)t.size();
				}
			}
			return j;
		}
	}

	static int16_t getBestMatch(const map<uint16_t, vector<string>>& lang1, const map<uint16_t, vector<string>>& lang2) {
		auto i = getBestMatch(lang2);
		if (i < 0) {
			i = getBestMatch(lang1);
		}
		return i;
	}

	static char* translateSubType(const TimedMetadataKind kind) {
		char* type = nullptr;
		if (kind == TimedMetadataKind::Custom) {
			type = "custom";
		} else if (kind == TimedMetadataKind::Data) {
			type = "data";
		} else if (kind == TimedMetadataKind::Description) {
			type = "description";
		} else if (kind == TimedMetadataKind::Speech) {
			type = "speech";
		} else if (kind == TimedMetadataKind::Caption) {
			type = "caption";
		} else if (kind == TimedMetadataKind::Chapter) {
			type = "chapter";
		} else if (kind == TimedMetadataKind::Subtitle) {
			type = "subtitle";
		} else if (kind == TimedMetadataKind::ImageSubtitle) {
			type = "imageSubtitle";
		}
		return type;
	}

	static void createDispatcherQueue() {
		check_hresult(CreateDispatcherQueueController(
			DispatcherQueueOptions{
				sizeof(DispatcherQueueOptions),
				DQTYPE_THREAD_CURRENT,
				DQTAT_COM_NONE
			},
			//PDISPATCHERQUEUECONTROLLER could be missing in some case, so we use the original type instead
			reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(dispatcherController))
		));
		dispatcherQueue = dispatcherController.DispatcherQueue();
	}

	static TextureVariant* createTextureVariant(weak_ptr<VideoController> weakThis, const bool isSubtitle) {
		return new TextureVariant(GpuSurfaceTexture(
			kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
			//kFlutterDesktopGpuSurfaceTypeD3d11Texture2D,
			[weakThis, isSubtitle](auto, auto) -> const FlutterDesktopGpuSurfaceDescriptor* {
				auto sharedThis = weakThis.lock();
				if (sharedThis && (!isSubtitle || sharedThis->showSubtitle)) {
					auto& buffer = isSubtitle ? sharedThis->subTextureBuffer : sharedThis->textureBuffer;
					if (buffer.visible_width > 0 && buffer.visible_height > 0) {
						auto& mtx = isSubtitle ? sharedThis->subtitleMutex : sharedThis->videoMutex;
						mtx.lock();
						return &buffer;
					}
				}
				return nullptr;
			}
		));
	}

	static void renderingCompleted(void* releaseContext) {
		auto mtx = (mutex*)releaseContext;
		mtx->unlock(); //this mutex is locked before we send the texture to flutter
	}

	static void drawFrame(weak_ptr<VideoController> weakThis, const bool isSubtitle) {
		auto sharedThis = weakThis.lock();
		if (sharedThis && (!isSubtitle || sharedThis->showSubtitle)) {
			auto& buffer = isSubtitle ? sharedThis->subTextureBuffer : sharedThis->textureBuffer;
			if (buffer.width > 0 && buffer.height > 0) {
				sharedThis->textureRegistrar->MarkTextureFrameAvailable(isSubtitle ? sharedThis->subtitleId : sharedThis->textureId);
				auto& mtx = isSubtitle ? sharedThis->subtitleMutex : sharedThis->videoMutex;
				mtx.lock();
				auto& surface = isSubtitle ? sharedThis->subtitleSurface : sharedThis->videoSurface;
				if (!surface || buffer.width != buffer.visible_width || buffer.height != buffer.visible_height) {
					buffer.visible_width = buffer.width;
					buffer.visible_height = buffer.height;
					D3D11_TEXTURE2D_DESC desc{
						(UINT)buffer.width,
						(UINT)buffer.height,
						1,
						1,
						DXGI_FORMAT_B8G8R8A8_UNORM,
						{ 1, DXGI_STANDARD_MULTISAMPLE_QUALITY_PATTERN },
						D3D11_USAGE_DEFAULT,
						D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE,
						0,
						D3D11_RESOURCE_MISC_SHARED
					};
					com_ptr<ID3D11Texture2D> d3d11Texture;
					check_hresult(d3dDevice->CreateTexture2D(&desc, nullptr, d3d11Texture.put()));
					//buffer->handle = d3d11Texture.get();
					if (isSubtitle) {
						check_hresult(d3dDevice->CreateRenderTargetView(d3d11Texture.get(), nullptr, sharedThis->subtitleRenderTargetView.put()));
					}
					com_ptr<IDXGIResource> resource;
					d3d11Texture.as(resource);
					check_hresult(resource->GetSharedHandle(&buffer.handle));
					com_ptr<IDXGISurface> dxgiSurface;
					d3d11Texture.as(dxgiSurface);
					if (surface) {
						surface.Close();
					}
					check_hresult(CreateDirect3D11SurfaceFromDXGISurface(dxgiSurface.get(), reinterpret_cast<IInspectable**>(put_abi(surface))));
				} else if (isSubtitle) {
					const float clearColor[]{ 0.0f, 0.0f, 0.0f, 0.0f };
					d3dContext->ClearRenderTargetView(sharedThis->subtitleRenderTargetView.get(), clearColor);
				}
				if (isSubtitle) {
					sharedThis->mediaPlayer.RenderSubtitlesToSurface(surface);
				} else {
					sharedThis->mediaPlayer.CopyFrameToVideoSurface(surface);
				}
				mtx.unlock();
			}
		}
	}

	EventChannel<EncodableValue>* eventChannel = nullptr;
	unique_ptr<EventSink<EncodableValue>> eventSink = nullptr;
	TextureRegistrar* textureRegistrar = nullptr;
	TextureVariant* texture = nullptr;
	TextureVariant* subTexture = nullptr;
	FlutterDesktopGpuSurfaceDescriptor textureBuffer{};
	FlutterDesktopGpuSurfaceDescriptor subTextureBuffer{};
	IDirect3DSurface videoSurface;
	IDirect3DSurface subtitleSurface;
	com_ptr<ID3D11RenderTargetView> subtitleRenderTargetView;
	MediaPlayer mediaPlayer = MediaPlayer();
	map<hstring, IMediaCue> cues;
	mutex videoMutex;
	mutex subtitleMutex;
	string source = "";
	int64_t position = 0;
	int64_t bufferPosition = 0;
	string preferredAudioLanguage = "";
	string preferredSubtitleLanguage = "";
	float volume = 1;
	float speed = 1;
	uint32_t maxBitrate = 0;
	uint16_t maxVideoWidth = 0;
	uint16_t maxVideoHeight = 0;
	int16_t overrideAudioTrack = -1;
	int16_t overrideSubtitleTrack = -1;
	bool looping = false;
	bool showSubtitle = false;
	bool networking = false;
	uint8_t state = 0; //0: idle, 1: opening, 2: ready, 3: playing

	int16_t getDefaultAudioTrack(const string& lang) {
		auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().AudioTracks();
		vector<string> toks;
		split(lang, '-', toks);
		map<uint16_t, vector<string>> lang1;
		map<uint16_t, vector<string>> lang2;
		for (uint16_t i = 0; i < tracks.Size(); i++) {
			vector<string> t;
			split(to_string(tracks.GetAt(i).Language()), '-', t);
			if (t[0] == toks[0]) {
				lang1[i] = t;
				if (t.size() > 1 && toks.size() > 1 && t[1] == toks[1]) {
					lang2[i] = t;
					if (t.size() > 2 && toks.size() > 2 && t[2] == toks[2]) {
						return i;
					}
				}
			}
		}
		return max<int16_t>(getBestMatch(lang1, lang2), tracks.Size() > 0 ? 0 : -1);
	}

	int16_t getDefaultSubtitleTrack(const string& lang) {
		auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().TimedMetadataTracks();
		vector<string> toks;
		split(lang, '-', toks);
		map<uint16_t, vector<string>> lang1;
		map<uint16_t, vector<string>> lang2;
		int16_t def = -1;
		for (uint16_t i = 0; i < tracks.Size(); i++) {
			auto track = tracks.GetAt(i);
			auto kind = track.TimedMetadataKind();
			if ((kind == TimedMetadataKind::Caption || kind == TimedMetadataKind::Subtitle || kind == TimedMetadataKind::ImageSubtitle)) {
				if (def < 0) {
					def = i;
				}
				if (to_string(track.Language()) == lang) {
					vector<string> t;
					split(to_string(tracks.GetAt(i).Language()), '-', t);
					if (t[0] == toks[0]) {
						lang1[i] = t;
						if (t.size() > 1 && toks.size() > 1 && t[1] == toks[1]) {
							lang2[i] = t;
							if (t.size() > 2 && toks.size() > 2 && t[2] == toks[2]) {
								return i;
							}
						}
					}
				}
			}
		}
		return max(getBestMatch(lang1, lang2), def);
	}

	int16_t getDefaultVideoTrack() {
		auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().VideoTracks();
		uint32_t maxRes = 0;
		uint32_t maxBit = 0;
		int16_t maxId = -1;
		uint32_t minRes = UINT32_MAX;
		uint32_t minBit = UINT32_MAX;
		int16_t minId = -1;
		for (uint16_t i = 0; i < tracks.Size(); i++) {
			auto props = tracks.GetAt(i).GetEncodingProperties();
			auto bitrate = props.Bitrate();
			auto width = props.Width();
			auto height = props.Height();
			uint32_t res = width * height;
			if ((maxVideoWidth == 0 || width == 0 || width <= maxVideoWidth) && (maxVideoHeight == 0 || height == 0 || height <= maxVideoHeight) && (maxBitrate == 0 || bitrate == 0 || bitrate <= maxBitrate)) {
				if (maxVideoHeight == 0 && maxVideoWidth == 0 && maxBitrate > 0) {
					if (bitrate > 0 && bitrate > maxBit) {
						maxBit = bitrate;
						maxId = i;
					}
				} else if (res > maxRes) {
					maxRes = res;
					maxId = i;
				}
			}
			if (maxId < 0) {
				if (maxVideoHeight == 0 && maxVideoWidth == 0 && maxBitrate > 0) {
					if (bitrate > 0 && bitrate < minBit) {
						minBit = bitrate;
						minId = i;
					}
				} else if (res < minRes) {
					minRes = res;
					minId = i;
				}
			}
		}
		if (maxId < 0) {
			maxId = minId;
		}
		return maxId < 0 && tracks.Size() > 0 ? 0 : maxId;
	}

	int16_t getDefaultTrack(const MediaTrackKind kind) {
		if (kind == MediaTrackKind::Video) {
			return getDefaultAudioTrack(preferredAudioLanguage);
		} else {
			int16_t index = -1;
			auto isSubtitle = kind == MediaTrackKind::TimedMetadata;
			if ((isSubtitle ? preferredSubtitleLanguage : preferredAudioLanguage).empty()) {
				auto langs = GlobalizationPreferences::Languages();
				for (auto lang : langs) {
					auto str = to_string(lang);
					transform(str.begin(), str.end(), str.begin(), lower);
					index = isSubtitle ? getDefaultSubtitleTrack(str) : getDefaultAudioTrack(str);
					if (index >= 0) {
						break;
					}
				}
			} else {
				index = isSubtitle ? getDefaultSubtitleTrack(preferredSubtitleLanguage) : getDefaultAudioTrack(preferredAudioLanguage);
			}
			return index;
		}
	}

	void setPosition() {
		if (!mediaPlayer.RealTimePlayback()) {
			auto pos = mediaPlayer.PlaybackSession().Position().count() / 10000;
			if (pos != position) {
				position = pos;
				if (eventSink) {
					eventSink->Success(EncodableMap{
						{ string("event"), string("position") },
						{ string("value"), EncodableValue(position) }
					});
				}
			}
		}
	}

	void sendBuffer(int64_t pos) {
		if (eventSink) {
			eventSink->Success(EncodableMap{
				{ string("event"), string("buffer") },
				{ string("start"), EncodableValue(pos) },
				{ string("end"), EncodableValue(bufferPosition) }
			});
		}
	}

	void loadEnd() {
		if (state == 1) {
			auto playbackSession = mediaPlayer.PlaybackSession();
			state = 2;
			mediaPlayer.Volume(volume);
			playbackSession.PlaybackRate(speed);
			EncodableMap audioTracks{};
			EncodableMap subtitleTracks{};
			auto item = mediaPlayer.Source().as<MediaPlaybackItem>();
			char id[16];
			auto audiotracks = item.AudioTracks();
			auto selectedAudioTrackId = getDefaultTrack(MediaTrackKind::Audio);
			if (selectedAudioTrackId >= 0 && audiotracks.SelectedIndex() != selectedAudioTrackId) {
				audiotracks.SelectedIndex(selectedAudioTrackId);
			}
			for (uint16_t i = 0; i < audiotracks.Size(); i++) {
				auto track = audiotracks.GetAt(i);
				auto props = track.GetEncodingProperties();
				auto title = track.Name();
				if (title.empty()) {
					title = track.Label();
				}
				sprintf_s(id, "%d.%d", MediaTrackKind::Audio, i);
				audioTracks[string(id)] = EncodableMap{
					{ string("title"), to_string(title) },
					{ string("language"), to_string(track.Language()) },
					{ string("format"), to_string(props.Subtype()) },
					{ string("bitRate"), EncodableValue((int32_t)props.Bitrate()) },
					{ string("channels"), EncodableValue((int32_t)props.ChannelCount()) },
					{ string("sampleRate"), EncodableValue((int32_t)props.SampleRate()) }
				};
			}
			auto subtitletracks = item.TimedMetadataTracks();
			auto selectedSubtitleTrackId = getDefaultTrack(MediaTrackKind::TimedMetadata);
			for (uint16_t i = 0; i < subtitletracks.Size(); i++) {
				auto track = subtitletracks.GetAt(i);
				auto kind = track.TimedMetadataKind();
				if (kind == TimedMetadataKind::Caption || kind == TimedMetadataKind::Subtitle || kind == TimedMetadataKind::ImageSubtitle) {
					if (selectedSubtitleTrackId >= 0) {
						subtitletracks.SetPresentationMode(i, i == selectedSubtitleTrackId ? TimedMetadataTrackPresentationMode::PlatformPresented : TimedMetadataTrackPresentationMode::Disabled);
					}
					auto title = track.Name();
					if (title.empty()) {
						title = track.Label();
					}
					sprintf_s(id, "%d.%d", MediaTrackKind::TimedMetadata, i);
					subtitleTracks[string(id)] = EncodableMap{
						{ string("title"), to_string(title) },
						{ string("language"), to_string(track.Language()) },
						{ string("format"), string(translateSubType(kind)) }
					};
				}
			}
			if (eventSink) {
				eventSink->Success(EncodableMap{
					{ string("event"), string("mediaInfo") },
					{ string("audioTracks"), audioTracks },
					{ string("subtitleTracks"), subtitleTracks },
					{ string("duration"), EncodableValue(mediaPlayer.RealTimePlayback() ? 0 : playbackSession.NaturalDuration().count() / 10000) },
					{ string("source"), source }
				});
				setPosition();
				if (networking && !mediaPlayer.RealTimePlayback() && bufferPosition > position) {
					sendBuffer(position);
				}
			}
		}
	}

public:
	static void initGlobal() {
		//init_apartment(apartment_type::single_threaded);
		dispatcherQueue = DispatcherQueue::GetForCurrentThread();
		if (dispatcherQueue) {
			dispatcherQueue.ShutdownStarting([](auto, DispatcherQueueShutdownStartingEventArgs args) {
				args.GetDeferral().Complete();
				createDispatcherQueue();
			});
		} else {
			createDispatcherQueue();
		}
		D3D_FEATURE_LEVEL featureLevel{};
		check_hresult(D3D11CreateDevice(
			nullptr,
			D3D_DRIVER_TYPE_HARDWARE,
			nullptr,
			D3D11_CREATE_DEVICE_BGRA_SUPPORT,
			nullptr,
			0,
			D3D11_SDK_VERSION,
			&d3dDevice,
			&featureLevel,
			&d3dContext
		));
	}

	static void uninitGlobal() {
		if (d3dDevice) {
			d3dDevice->Release();
			d3dContext->Release();
		}
		if (dispatcherController) {
			dispatcherController.ShutdownQueueAsync();
			dispatcherController = nullptr;
		}
		dispatcherQueue = nullptr;
		//uninit_apartment();
	}

	int64_t textureId = 0;
	int64_t subtitleId = 0;

	VideoController() {
		textureBuffer.struct_size = subTextureBuffer.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
		textureBuffer.format = subTextureBuffer.format = kFlutterDesktopPixelFormatBGRA8888;
		textureBuffer.release_callback = subTextureBuffer.release_callback = renderingCompleted;
		textureBuffer.release_context = &videoMutex;
		subTextureBuffer.release_context = &subtitleMutex;
		mediaPlayer.IsVideoFrameServerEnabled(true);
		mediaPlayer.CommandManager().IsEnabled(false);
	}

	~VideoController() {
		mediaPlayer.Close();
		if (textureRegistrar) {
			textureRegistrar->UnregisterTexture(textureId);
			delete texture;
			delete subTexture;
		}
		if (videoSurface) {
			videoSurface.Close();
		}
		if (subtitleSurface) {
			subtitleSurface.Close();
		}
		if (eventSink) {
			//eventSink->EndOfStream();
			eventSink = nullptr;
		}
		if (eventChannel) {
			//eventChannel->SetStreamHandler(nullptr);
			delete eventChannel;
		}
	}

	void init(PluginRegistrarWindows& registrar) {
		auto weakThis = weak_from_this();
		textureRegistrar = registrar.texture_registrar();
		texture = createTextureVariant(weakThis, false);
		subTexture = createTextureVariant(weakThis, true);
		textureId = textureRegistrar->RegisterTexture(texture);
		subtitleId = textureRegistrar->RegisterTexture(subTexture);
		char id[32];
		sprintf_s(id, "VideoViewPlugin/%lld", textureId);
		eventChannel = new EventChannel<EncodableValue>(
			registrar.messenger(),
			id,
			&StandardMethodCodec::GetInstance()
		);
		eventChannel->SetStreamHandler(make_unique<StreamHandlerFunctions<EncodableValue>>(
			[weakThis](const EncodableValue* arguments, unique_ptr<EventSink<EncodableValue>>&& events) {
				auto sharedThis = weakThis.lock();
				if (sharedThis) {
					sharedThis->eventSink = move(events);
				}
				return nullptr;
			},
			[weakThis](const EncodableValue* arguments) {
				auto sharedThis = weakThis.lock();
				if (sharedThis) {
					sharedThis->eventSink = nullptr;
				}
				return nullptr;
			}
		));
		auto playbackSession = mediaPlayer.PlaybackSession();

		playbackSession.NaturalVideoSizeChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 0) {
					sharedThis->textureBuffer.width = sharedThis->subTextureBuffer.width = playbackSession.NaturalVideoWidth();
					sharedThis->textureBuffer.height = sharedThis->subTextureBuffer.height = playbackSession.NaturalVideoHeight();
					if (sharedThis->eventSink) {
						sharedThis->eventSink->Success(EncodableMap{
							{ string("event"), string("videoSize") },
							{ string("width"), EncodableValue((double)sharedThis->textureBuffer.width) },
							{ string("height"), EncodableValue((double)sharedThis->textureBuffer.height) }
						});
					}
				}
			}));
		});

		playbackSession.PositionChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 1) {
					sharedThis->setPosition();
				}
			}));
		});

		playbackSession.SeekCompleted([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->eventSink) {
					if (sharedThis->state == 1) {
						sharedThis->loadEnd();
					} else if (sharedThis->state > 1) {
						sharedThis->eventSink->Success(EncodableMap{
							{ string("event"), string("seekEnd") }
						});
					}
				}
			}));
		});

		playbackSession.BufferingStarted([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2 && sharedThis->eventSink) {
					sharedThis->eventSink->Success(EncodableMap{
						{ string("event"), string("loading") },
						{ string("value"), EncodableValue(true) }
					});
				}
			}));
		});

		playbackSession.BufferingEnded([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2 && sharedThis->eventSink) {
					sharedThis->eventSink->Success(EncodableMap{
						{ string("event"), string("loading") },
						{ string("value"), EncodableValue(false) }
					});
				}
			}));
		});

		playbackSession.BufferedRangesChanged([weakThis](MediaPlaybackSession playbackSession, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, playbackSession]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 0 && sharedThis->networking && !sharedThis->mediaPlayer.RealTimePlayback()) {
					auto buffered = playbackSession.GetBufferedRanges();
					for (uint32_t i = 0; i < buffered.Size(); i++) {
						auto start = buffered.GetAt(i).Start.count();
						auto end = buffered.GetAt(i).End.count();
						auto pos = playbackSession.Position().count();
						if (start <= pos && end >= pos) {
							auto t = end / 10000;
							if (sharedThis->bufferPosition != t) {
								sharedThis->bufferPosition = t;
								if (sharedThis->state > 1) {
									sharedThis->sendBuffer(pos / 10000);
								}
							}
							break;
						}
					}
				}
			}));
		});

		mediaPlayer.SubtitleFrameChanged([weakThis](auto, auto) {
			drawFrame(weakThis, true);
		});

		mediaPlayer.VideoFrameAvailable([weakThis](auto, auto) {
			drawFrame(weakThis, false);
		});

		mediaPlayer.MediaFailed([weakThis](auto, MediaPlayerFailedEventArgs const& reason) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis, reason]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 0) {
					sharedThis->close();
					if (sharedThis->eventSink) {
						auto message = "Unknown";
						auto err = reason.Error();
						if (err == MediaPlayerError::Aborted) {
							message = "Aborted";
						} else if (err == MediaPlayerError::NetworkError) {
							message = "NetworkError";
						} else if (err == MediaPlayerError::DecodingError) {
							message = "DecodingError";
						} else if (err == MediaPlayerError::SourceNotSupported) {
							message = "SourceNotSupported";
						}
						sharedThis->eventSink->Success(EncodableMap{
							{ string("event"), string("error") },
							{ string("value"), string(message) }
						});
					}
				}
			}));
		});

		mediaPlayer.MediaOpened([weakThis](auto, auto) {
			auto sharedThis = weakThis.lock();
			if (sharedThis && sharedThis->state == 1) {
				auto playbackSession = sharedThis->mediaPlayer.PlaybackSession();
				auto live = playbackSession.NaturalDuration().count() == INT64_MAX;
				sharedThis->mediaPlayer.RealTimePlayback(live);
				if (live) {
					dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
						auto sharedThis = weakThis.lock();
						if (sharedThis) {
							sharedThis->loadEnd();
						}
					}));
				} else {
					playbackSession.Position(chrono::milliseconds(sharedThis->position));
					sharedThis->position = 0;
				}
			}
		});

		mediaPlayer.MediaEnded([weakThis](auto, auto) {
			dispatcherQueue.TryEnqueue(DispatcherQueueHandler([weakThis]() {
				auto sharedThis = weakThis.lock();
				if (sharedThis && sharedThis->state > 2) {
					if (sharedThis->mediaPlayer.RealTimePlayback()) {
						sharedThis->close();
					} else if (sharedThis->looping) {
						sharedThis->mediaPlayer.Play();
					} else {
						sharedThis->state = 2;
					}
					if (sharedThis->eventSink) {
						sharedThis->eventSink->Success(EncodableMap{
							{ string("event"), string("finished") }
						});
					}
				}
			}));
		});
	}

	void open(const string& src) {
		close();
		hstring url;
		if (src._Starts_with("asset://")) {
			wchar_t path[MAX_PATH];
			GetModuleFileNameW(nullptr, path, MAX_PATH);
			wstring sourceUrl(L"file://");
			sourceUrl += path;
			sourceUrl.replace(sourceUrl.find_last_of(L'\\') + 1, sourceUrl.length(), L"data/flutter_assets/");
			sourceUrl += wstring(src.begin() + 8, src.end());
			replace(sourceUrl.begin(), sourceUrl.end(), L'\\', L'/');
			url = sourceUrl;
		} else if (src.find("://") == string::npos) {
			wstring sourceUrl(L"file://");
			sourceUrl += wstring(src.begin(), src.end());
			replace(sourceUrl.begin(), sourceUrl.end(), L'\\', L'/');
			url = sourceUrl;
		} else {
			url = to_hstring(src);
			networking = !src._Starts_with("file://");
		}
		source = src;
		state = 1;
		mediaPlayer.Source(MediaPlaybackItem(MediaSource::CreateFromUri(winrt::Windows::Foundation::Uri(url))));
	}

	void close() {
		state = 0;
		textureBuffer.width = textureBuffer.height = subTextureBuffer.width = subTextureBuffer.height = 0;
		if (videoSurface) {
			videoSurface.Close();
			videoSurface = nullptr;
		}
		if (subtitleSurface) {
			subtitleSurface.Close();
			subtitleSurface = nullptr;
		}
		position = 0;
		bufferPosition = 0;
		overrideAudioTrack = -1;
		overrideSubtitleTrack = -1;
		source = "";
		networking = false;
		auto src = mediaPlayer.Source();
		if (src) {
			mediaPlayer.Source(nullptr);
			src.as<MediaPlaybackItem>().Source().Close();
		}
	}

	void play() {
		if (state == 2) {
			state = 3;
			mediaPlayer.Play();
		}
	}

	void pause() {
		if (state > 2) {
			state = 2;
			mediaPlayer.Pause();
		}
	}

	void seekTo(int64_t pos) {
		auto playbackSession = mediaPlayer.PlaybackSession();
		if (state == 1) {
			position = pos;
		} else if (eventSink && (!mediaPlayer.Source() || mediaPlayer.RealTimePlayback() || playbackSession.Position().count() / 10000 == pos)) {
			eventSink->Success(EncodableMap{
				{ string("event"), string("seekEnd") }
			});
		} else if (state > 1) {
			playbackSession.Position(chrono::milliseconds(pos));
		}
	}

	void setVolume(float vol) {
		volume = vol;
		mediaPlayer.Volume(vol);
	}

	void setSpeed(float spd) {
		speed = spd;
		mediaPlayer.PlaybackSession().PlaybackRate(speed);
	}

	void setLooping(bool loop) {
		looping = loop;
	}

	void setShowSubtitle(bool show) {
		showSubtitle = show;
	}

	void setMaxResolution(int16_t width, uint16_t height) {
		maxVideoWidth = width;
		maxVideoHeight = height;
		if (state > 1) {
			auto i = getDefaultTrack(MediaTrackKind::Video);
			if (i >= 0) {
				auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().VideoTracks();
				if (tracks.SelectedIndex() != i) {
					tracks.SelectedIndex(i);
				}
			}
		}
	}

	void setMaxBitRate(uint32_t bitrate) {
		maxBitrate = bitrate;
		if (state > 1) {
			auto i = getDefaultTrack(MediaTrackKind::Video);
			if (i >= 0) {
				auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().VideoTracks();
				if (tracks.SelectedIndex() != i) {
					tracks.SelectedIndex(i);
				}
			}
		}
	}

	void setPreferredAudioLanguage(const string& lang) {
		preferredAudioLanguage = lang;
		if (state > 1 && overrideAudioTrack < 0) {
			auto i = getDefaultTrack(MediaTrackKind::Audio);
			if (i >= 0) {
				auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().AudioTracks();
				if (tracks.SelectedIndex() != i) {
					tracks.SelectedIndex(i);
				}
			}
		}
	}

	void setPreferredSubtitleLanguage(const string& lang) {
		preferredSubtitleLanguage = lang;
		if (state > 1 && overrideSubtitleTrack < 0) {
			auto j = getDefaultTrack(MediaTrackKind::TimedMetadata);
			auto tracks = mediaPlayer.Source().as<MediaPlaybackItem>().TimedMetadataTracks();
			for (uint16_t i = 0; i < tracks.Size(); i++) {
				auto k = tracks.GetAt(i).TimedMetadataKind();
				if (k == TimedMetadataKind::Caption || k == TimedMetadataKind::Subtitle || k == TimedMetadataKind::ImageSubtitle) {
					tracks.SetPresentationMode(i, i == j ? TimedMetadataTrackPresentationMode::PlatformPresented : TimedMetadataTrackPresentationMode::Disabled);
				}
			}
		}
	}

	void overrideTrack(MediaTrackKind kind, int16_t trackId, bool enabled) {
		if (state > 1) {
			auto item = mediaPlayer.Source().as<MediaPlaybackItem>();
			if (kind == MediaTrackKind::Audio) {
				auto tracks = item.AudioTracks();
				tracks.SelectedIndex(enabled ? trackId : max(getDefaultTrack(kind), (int16_t)0));
				overrideAudioTrack = enabled ? trackId : -1;
			} else if (kind == MediaTrackKind::TimedMetadata) {
				auto tracks = item.TimedMetadataTracks();
				if (!enabled) {
					trackId = getDefaultTrack(kind);
				}
				for (uint16_t i = 0; i < tracks.Size(); i++) {
					auto k = tracks.GetAt(i).TimedMetadataKind();
					if (k == TimedMetadataKind::Caption || k == TimedMetadataKind::Subtitle || k == TimedMetadataKind::ImageSubtitle) {
						tracks.SetPresentationMode(i, i == trackId ? TimedMetadataTrackPresentationMode::PlatformPresented : TimedMetadataTrackPresentationMode::Disabled);
					}
				}
				overrideSubtitleTrack = enabled ? trackId : -1;
			}
		}
	}
};
ID3D11DeviceContext* VideoController::d3dContext = nullptr;
ID3D11Device* VideoController::d3dDevice = nullptr;
DispatcherQueueController VideoController::dispatcherController{ nullptr };
DispatcherQueue VideoController::dispatcherQueue{ nullptr };

class VideoViewPlugin : public Plugin {
	MethodChannel<EncodableValue>* methodChannel;
	map<int64_t, shared_ptr<VideoController>> players;
	string Id = "id";
	string Value = "value";

public:
	VideoViewPlugin(PluginRegistrarWindows& registrar) {
		VideoController::initGlobal();
		methodChannel = new MethodChannel<EncodableValue>(
			registrar.messenger(),
			"VideoViewPlugin",
			&StandardMethodCodec::GetInstance()
		);

		methodChannel->SetMethodCallHandler([&](const MethodCall<EncodableValue>& call, unique_ptr<MethodResult<EncodableValue>> result) {
			auto returned = false;
			auto& methodName = call.method_name();
			if (methodName == "create") {
				auto player = make_shared<VideoController>();
				player->init(registrar);
				players[player->textureId] = player;
				result->Success(EncodableMap{
					{ string("id"), EncodableValue(player->textureId) },
					{ string("subId"), EncodableValue(player->subtitleId) }
				});
				returned = true;
			} else if (methodName == "dispose") {
				if (call.arguments()->IsNull()) {
					players.clear();
				} else {
					players.erase(call.arguments()->LongValue());
				}
			} else if (methodName == "close") {
				auto& player = players[call.arguments()->LongValue()];
				player->close();
			} else if (methodName == "play") {
				auto& player = players[call.arguments()->LongValue()];
				player->play();
			} else if (methodName == "pause") {
				auto& player = players[call.arguments()->LongValue()];
				player->pause();
			} else if (methodName == "open") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto& src = get<string>(args.at(Value));
				player->open(src);
			} else if (methodName == "seekTo") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto pos = args.at(string("position")).LongValue();
				player->seekTo(pos);
			} else if (methodName == "setVolume") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto vol = get<double>(args.at(Value));
				player->setVolume((float)vol);
			} else if (methodName == "setSpeed") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto spd = get<double>(args.at(Value));
				player->setSpeed((float)spd);
			} else if (methodName == "setLooping") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto loop = get<bool>(args.at(Value));
				player->setLooping(loop);
			} else if (methodName == "setMaxResolution") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto width = get<double>(args.at(string("width")));
				auto height = get<double>(args.at(string("height")));
				player->setMaxResolution((uint16_t)width, (uint16_t)height);
			} else if (methodName == "setMaxBitRate") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto bitrate = args.at(Value).LongValue();
				player->setMaxBitRate((uint32_t)bitrate);
			} else if (methodName == "setPreferredSubtitleLanguage") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto& lang = get<string>(args.at(Value));
				player->setPreferredSubtitleLanguage(lang);
			} else if (methodName == "setPreferredAudioLanguage") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto& lang = get<string>(args.at(Value));
				player->setPreferredAudioLanguage(lang);
			} else if (methodName == "setShowSubtitle") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto show = get<bool>(args.at(Value));
				player->setShowSubtitle(show);
			} else if (methodName == "overrideTrack") {
				auto& args = get<EncodableMap>(*call.arguments());
				auto& player = players[args.at(Id).LongValue()];
				auto kind = get<int32_t>(args.at(string("groupId")));
				auto trackId = get<int32_t>(args.at(string("trackId")));
				auto enabled = get<bool>(args.at(string("enabled")));
				player->overrideTrack((MediaTrackKind)kind, (int16_t)trackId, enabled);
			} else {
				result->NotImplemented();
				returned = true;
			}
			if (!returned) {
				result->Success();
			}
		});
	}

	virtual ~VideoViewPlugin() {
		players.clear();
		//methodChannel->SetMethodCallHandler(nullptr);
		delete methodChannel;
		VideoController::uninitGlobal();
	}

	VideoViewPlugin(const VideoViewPlugin&) = delete;
	VideoViewPlugin& operator=(const VideoViewPlugin&) = delete;
};

void VideoViewPluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrarRef) {
	auto& registrar = *PluginRegistrarManager::GetInstance()->GetRegistrar<PluginRegistrarWindows>(registrarRef);
	registrar.AddPlugin(make_unique<VideoViewPlugin>(registrar));
}