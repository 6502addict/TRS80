#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include "kbd_ringbuffer.h"

KbdRingBuffer *KbdRingBufferCreate() {
  KbdRingBuffer *krb = (KbdRingBuffer *) calloc(1, sizeof(KbdRingBuffer));

  krb->head = 0;
  krb->tail = 0;
  krb->size = 0;
  krb->maxsize = KBD_BUFFER_SIZE;
  return krb;
}

bool isKbdRingBufferEmpty(KbdRingBuffer *krb) {
  return krb->size == 0;
}

bool isKbdRingBufferFull(KbdRingBuffer *krb) {
  return krb->size == krb->maxsize;
}

bool KbdAddKey(KbdRingBuffer *krb, uint16_t keycode) {
  if (isKbdRingBufferFull(krb)) 
    false;
  krb->data[krb->tail] = keycode;
  krb->tail = (krb->tail + 1) % krb->maxsize;
  krb->size++;
  return true;
}

bool KbdGetKey(KbdRingBuffer *krb, uint16_t *keycode) {
  if (isKbdRingBufferEmpty(krb)) 
    return false;
  *keycode = krb->data[krb->head];
  krb->head = (krb->head + 1) % krb->maxsize;
  krb->size--;
  return true;
}

void KbdRingBufferDump(KbdRingBuffer *krb) {
  if (isKbdRingBufferEmpty(krb)) 
    return;
  int index = krb->head;
  for (int i = 0; i < krb->size; i++) {
    printf("%4.0x ", krb->data[index]);
    index = (index + 1) % krb->maxsize;
  }
  printf("\n");
}

void KbdRingBufferRelease(KbdRingBuffer *krb) {
  free(krb);
}
