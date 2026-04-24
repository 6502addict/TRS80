#define KBD_BUFFER_SIZE 128

typedef struct {
  uint16_t data[KBD_BUFFER_SIZE];
  int head;
  int tail;
  int size;
  int maxsize;
} KbdRingBuffer;

KbdRingBuffer *KbdRingBufferCreate(); 
bool           isKbdRingBufferEmpty(KbdRingBuffer *);
bool           isKbdRingBufferFull(KbdRingBuffer *);
bool           KbdAddKey(KbdRingBuffer *, uint16_t);
bool           KbdGetKey(KbdRingBuffer *, uint16_t *);
void           KbdRingBufferDump(KbdRingBuffer *);
void           KbdRingBufferRelease(KbdRingBuffer *);

