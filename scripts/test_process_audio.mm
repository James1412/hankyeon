// Exercise the actual HAL callback with synthetic buffers; no devices or taps are opened.
#include "../macos/Runner/Audio/ProcessAudio.mm"
#include <cassert>
#include <iostream>
int main() {
    constexpr uint32_t frames = 1024;
    float samples[frames * 2], result[frames * 2];
    std::fill_n(samples, frames * 2, .25f);
    AudioBufferList in{1, {{2, sizeof(samples), samples}}};
    AudioBufferList out{1, {{2, sizeof(result), result}}};
    Route route;
    route.gain.store(.5f);
    render(0, nullptr, &in, nullptr, &out, nullptr, &route);
    assert(result[0] > .125f); // Smooth transition, never an abrupt gain discontinuity.
    assert(std::abs(result[frames * 2 - 1] - .125f) < .000001f);
    assert(std::abs(route.peak.load() - .25f) < .000001f);
    assert(HankyeonAudioReadOutputPeak(&route) > .125f);
    route.monitor = true;
    std::fill_n(result, frames * 2, 1.0f);
    render(0, nullptr, &in, nullptr, &out, nullptr, &route);
    for (float value : result) assert(value == 0); // Permission probe never doubles audio.
    assert(HankyeonAudioReadOutputPeak(&route) == 0);
    route.monitor = false; route.gain.store(0);
    render(0, nullptr, &in, nullptr, &out, nullptr, &route);
    assert(result[frames * 2 - 1] == 0);
    render(0, nullptr, nullptr, nullptr, &out, nullptr, &route);
    for (float value : result) assert(value == 0);
    HankyeonAudioDestroy(nullptr);
    std::cout << "DSP gain ramp, silence, peak, monitor-only and cleanup passed\n";
}
