#ifndef HANKYEON_AUDIO_BRIDGE_H
#define HANKYEON_AUDIO_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Control calls run on one serial queue. The HAL callback only touches atomics.
void *HankyeonAudioCreate(const uint32_t *processes, uint32_t count, float gain, int muted, int32_t *status);
float HankyeonAudioReadOutputPeak(void *handle);
float HankyeonAudioReadPeak(void *handle);
void HankyeonAudioSetGain(void *handle, float gain);
void HankyeonAudioDestroy(void *handle);
int32_t HankyeonAudioProbe(void);
#ifdef __cplusplus
}
#endif

#endif
