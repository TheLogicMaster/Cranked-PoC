// Browser front end: plays the interleaved 16-bit stereo chunks the engine worker sends (over a MessagePort).
// About 60 ms is buffered before playing; an underrun plays silence and waits for that much again, and when more than
// 250 ms is queued (the worker's clock running ahead of the audio clock) the oldest chunks are dropped.
class CrankedAudio extends AudioWorkletProcessor {
  constructor() {
    super();
    this.queue = []; this.offset = 0; this.queued = 0; this.started = false;
    this.port.onmessage = e => { if (e.data && e.data.port) e.data.port.onmessage = m => this.push(m.data); };
  }
  push(chunk) {
    this.queue.push(chunk); this.queued += chunk.length / 2;
    const max = sampleRate * 0.25;
    while (this.queued > max && this.queue.length > 1) { const old = this.queue.shift(); this.queued -= (old.length - this.offset) / 2; this.offset = 0; }
  }
  process(inputs, outputs) {
    const left = outputs[0][0], right = outputs[0][1] || outputs[0][0];
    if (!this.started && this.queued >= sampleRate * 0.06) this.started = true;
    for (let i = 0; i < left.length; i++) {
      if (!this.started || !this.queue.length) { left[i] = right[i] = 0; continue; }
      const chunk = this.queue[0];
      left[i] = chunk[this.offset] / 32768; right[i] = chunk[this.offset + 1] / 32768;
      this.offset += 2; this.queued--;
      if (this.offset >= chunk.length) { this.queue.shift(); this.offset = 0; }
    }
    if (!this.queue.length) this.started = false; // underrun: wait for the buffer to fill again
    return true;
  }
}
registerProcessor("cranked-audio", CrankedAudio);
