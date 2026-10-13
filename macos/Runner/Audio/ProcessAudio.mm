#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <Foundation/Foundation.h>
#include <atomic>
#include <algorithm>
#include <cmath>
#include <unistd.h>
#include "AudioBridge.h"

namespace {
static_assert(std::atomic<float>::is_always_lock_free, "Audio gain must be lock free");
struct Route {
    AudioObjectID tap = 0, aggregate = 0;
    AudioDeviceIOProcID io = nullptr;
    std::atomic<float> gain{1}, peak{0}, outputPeak{0};
    float previous = 1, step = 1.0f / 480;
    uint32_t channels = 2;
    bool planar = false, monitor = false, running = false;
};
AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal) {
    return {selector, scope, kAudioObjectPropertyElementMain};
}
template <typename T> OSStatus read(AudioObjectID object, AudioObjectPropertySelector selector, T &value,
                                    AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal) {
    auto a = address(selector, scope); UInt32 bytes = sizeof(value);
    return AudioObjectGetPropertyData(object, &a, 0, nullptr, &bytes, &value);
}
bool floatPCM(const AudioStreamBasicDescription &f) {
    return f.mFormatID == kAudioFormatLinearPCM && (f.mFormatFlags & kAudioFormatFlagIsFloat) && f.mBitsPerChannel == 32;
}
// No allocation, locks, logging, Swift or Objective-C work on the audio thread.
OSStatus render(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *input,
                const AudioTimeStamp *, AudioBufferList *output, const AudioTimeStamp *, void *context) {
    auto &r = *static_cast<Route *>(context);
    for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData) memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    const UInt32 sourceCount = r.planar ? r.channels : 1;
    if (!input || input->mNumberBuffers < sourceCount) return noErr;
    const UInt32 first = input->mNumberBuffers - sourceCount; // Hardware inputs precede tap inputs.
    const auto &head = input->mBuffers[first];
    if (!head.mData || !head.mNumberChannels) return noErr;
    const UInt32 frames = head.mDataByteSize / (sizeof(float) * head.mNumberChannels);
    const float target = r.gain.load(std::memory_order_relaxed);
    float peak = 0, outputPeak = 0;
    for (UInt32 frame = 0; frame < frames; ++frame) {
        r.previous += std::clamp(target - r.previous, -r.step, r.step);
        UInt32 outputChannel = 0;
        for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
            auto &dest = output->mBuffers[b];
            auto *samples = static_cast<float *>(dest.mData);
            if (!samples || !dest.mNumberChannels || frame >= dest.mDataByteSize / (sizeof(float) * dest.mNumberChannels)) continue;
            for (UInt32 channel = 0; channel < dest.mNumberChannels; ++channel, ++outputChannel) {
                const UInt32 sourceChannel = r.channels == 1 ? 0 : outputChannel;
                if (sourceChannel >= r.channels) continue;
                const auto &source = input->mBuffers[first + (r.planar ? sourceChannel : 0)];
                const UInt32 offset = r.planar ? frame : frame * source.mNumberChannels + sourceChannel;
                if (!source.mData || offset >= source.mDataByteSize / sizeof(float)) continue;
                const float value = static_cast<const float *>(source.mData)[offset];
                peak = std::max(peak, std::abs(value));
                if (!r.monitor) {
                    const float processed = value * r.previous;
                    samples[frame * dest.mNumberChannels + channel] = processed;
                    outputPeak = std::max(outputPeak, std::abs(processed));
                }
            }
        }
    }
    r.peak.store(std::max(peak, r.peak.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    r.outputPeak.store(std::max(outputPeak, r.outputPeak.load(std::memory_order_relaxed)), std::memory_order_relaxed);
    return noErr;
}
void destroy(Route *r) {
    if (!r) return;
    if (r->running) AudioDeviceStop(r->aggregate, r->io);
    if (r->io) AudioDeviceDestroyIOProcID(r->aggregate, r->io);
    if (r->aggregate) AudioHardwareDestroyAggregateDevice(r->aggregate);
    if (@available(macOS 14.2, *)) { if (r->tap) AudioHardwareDestroyProcessTap(r->tap); }
    delete r;
}
}

void *HankyeonAudioCreate(const uint32_t *processes, uint32_t count, float gain, int muted, int32_t *status) {
    if (@available(macOS 14.2, *)) {
        *status = noErr;
        auto *r = new Route;
        r->gain.store(gain); r->previous = gain; r->monitor = !muted;
        AudioObjectID device = 0;
        CFStringRef uid = nullptr;
        *status = read(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice, device);
        if (*status == noErr) *status = read(device, kAudioDevicePropertyDeviceUID, uid);
        if (*status != noErr || !uid) { destroy(r); return nullptr; }
        NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
        for (UInt32 i = 0; i < count; ++i) [ids addObject:@(processes[i])];
        CATapDescription *description = [[CATapDescription alloc] initStereoMixdownOfProcesses:ids];
        description.name = @"Hankyeon app volume";
        description.privateTap = YES;
        description.muteBehavior = muted ? CATapMutedWhenTapped : CATapUnmuted;
        *status = AudioHardwareCreateProcessTap(description, &r->tap);
        AudioStreamBasicDescription format = {};
        if (*status == noErr) *status = read(r->tap, kAudioTapPropertyFormat, format);
        if (*status == noErr && !floatPCM(format)) *status = kAudioDeviceUnsupportedFormatError;
        r->channels = format.mChannelsPerFrame;
        r->planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved;
        NSDictionary *composition = @{
            @kAudioAggregateDeviceNameKey: @"Hankyeon app volume",
            @kAudioAggregateDeviceUIDKey: [@"com.hankyeon.route." stringByAppendingString:NSUUID.UUID.UUIDString],
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceIsStackedKey: @NO,
            @kAudioAggregateDeviceMainSubDeviceKey: (__bridge NSString *)uid,
            @kAudioAggregateDeviceSubDeviceListKey: @[@{@kAudioSubDeviceUIDKey: (__bridge NSString *)uid}],
            @kAudioAggregateDeviceTapListKey: @[@{
                @kAudioSubTapUIDKey: description.UUID.UUIDString,
                @kAudioSubTapDriftCompensationKey: @YES}],
        };
        if (*status == noErr) *status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &r->aggregate);
        CFRelease(uid);
        AudioStreamBasicDescription outputFormat = {};
        if (*status == noErr) *status = read(r->aggregate, kAudioDevicePropertyStreamFormat, outputFormat, kAudioObjectPropertyScopeOutput);
        if (*status == noErr && (!floatPCM(outputFormat) || outputFormat.mChannelsPerFrame < 2)) *status = kAudioDeviceUnsupportedFormatError;
        if (outputFormat.mSampleRate > 0) r->step = 1.0f / (0.01f * outputFormat.mSampleRate);
        if (*status == noErr) *status = AudioDeviceCreateIOProcID(r->aggregate, render, r, &r->io);
        if (*status == noErr) *status = AudioDeviceStart(r->aggregate, r->io);
        r->running = *status == noErr;
        if (*status != noErr) { destroy(r); return nullptr; }
        return r;
    }
    *status = kAudioHardwareUnsupportedOperationError; return nullptr;
}
float HankyeonAudioReadOutputPeak(void *handle) {
    return handle ? static_cast<Route *>(handle)->outputPeak.exchange(0, std::memory_order_relaxed) : 0;
}
float HankyeonAudioReadPeak(void *handle) {
    return handle ? static_cast<Route *>(handle)->peak.exchange(0, std::memory_order_relaxed) : 0;
}
void HankyeonAudioSetGain(void *handle, float gain) {
    if (handle) static_cast<Route *>(handle)->gain.store(std::clamp(gain, 0.0f, 1.0f), std::memory_order_relaxed);
}
void HankyeonAudioDestroy(void *handle) { destroy(static_cast<Route *>(handle)); }

namespace {
struct Tone { double phase = 0, rate = 48000; };
OSStatus toneRender(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *, const AudioTimeStamp *,
                    AudioBufferList *out, const AudioTimeStamp *, void *context) {
    auto &t = *static_cast<Tone *>(context);
    for (UInt32 b = 0; b < out->mNumberBuffers; ++b) {
        auto &buffer = out->mBuffers[b];
        auto *p = static_cast<float *>(buffer.mData);
        if (!p || !buffer.mNumberChannels) continue;
        const UInt32 frames = buffer.mDataByteSize / (sizeof(float) * buffer.mNumberChannels);
        for (UInt32 f = 0; f < frames; ++f) {
            const float value = 0.00003f * std::sin(2 * M_PI * 997 * (t.phase + f) / t.rate);
            for (UInt32 c = 0; c < buffer.mNumberChannels; ++c) p[f * buffer.mNumberChannels + c] = value;
        }
        if (b + 1 == out->mNumberBuffers) t.phase += frames;
    }
    return noErr;
}
}
// Tap only our own -90 dB test signal, never another app, before enabling routing.
int32_t HankyeonAudioProbe(void) {
    if (@available(macOS 14.2, *)) {
        auto a = address(kAudioHardwarePropertyTranslatePIDToProcessObject);
        pid_t pid = getpid(); AudioObjectID process = 0; UInt32 bytes = sizeof(process);
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof(pid), &pid, &bytes, &process);
        if (status != noErr || !process) return status ? status : -1;
        void *handle = HankyeonAudioCreate(&process, 1, 0, false, &status);
        if (!handle) return status;
        AudioObjectID device = 0; AudioStreamBasicDescription format = {};
        status = read(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice, device);
        if (!status) status = read(device, kAudioDevicePropertyStreamFormat, format, kAudioObjectPropertyScopeOutput);
        Tone tone; tone.rate = format.mSampleRate;
        AudioDeviceIOProcID io = nullptr;
        if (!status && !floatPCM(format)) status = kAudioDeviceUnsupportedFormatError;
        if (!status) status = AudioDeviceCreateIOProcID(device, toneRender, &tone, &io);
        if (!status) status = AudioDeviceStart(device, io);
        if (!status) {
            for (int i = 0; i < 40; ++i) {
                usleep(50000);
                if (static_cast<Route *>(handle)->peak.load(std::memory_order_relaxed) > 0.000003f) break;
            }
            status = static_cast<Route *>(handle)->peak.load() > 0.000003f ? noErr : -70001;
        }
        if (io) { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io); }
        HankyeonAudioDestroy(handle);
        return status;
    }
    return kAudioHardwareUnsupportedOperationError;
}
