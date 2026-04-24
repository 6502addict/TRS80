#include <stdio.h>
#include "pico/stdlib.h"
#include <stdlib.h>
#include <string.h>
#include "hardware/timer.h"
#include "hardware/uart.h"
#include "bsp/board.h"
#include "tusb.h"
#include "kbd_ringbuffer.h"
#include "kbd.h"

#define SERIAL         0
#define KBD_LANG       LANG_FR      // LANG_FR, LANG_EN
#define UART_ID        uart0
#define UART_TX_PIN    0
#define UART_RX_PIN    1
#define UART_BAUD      115200

//#define DEBUG
#ifdef DEBUG
#define DEBUG_UART     uart1
#define DEBUG_TX_PIN   4
#define DEBUG_RX_PIN   5
#define DEBUG_BAUD     115200
#endif

int kbd_decode_trs80(KbdRingBuffer *, uint8_t, uint8_t, bool);

bool debug = false;
bool hid_debug = false;
KbdRingBuffer *krb = NULL;
uint8_t lang = KBD_LANG;

void kbd_init(void) {
  gpio_init(UART_TX_PIN);
  gpio_set_dir(UART_TX_PIN, GPIO_OUT);
  gpio_put(UART_TX_PIN, 1);         
  gpio_set_function(UART_TX_PIN, GPIO_FUNC_UART);
  gpio_set_function(UART_RX_PIN, GPIO_FUNC_UART);
  uart_init(UART_ID, UART_BAUD);
  uart_set_format(UART_ID, 8, 1, UART_PARITY_NONE);
  sleep_ms(10);
}

void kbd_send(uint8_t ch) {
  uart_write_blocking(UART_ID, &ch, 1);
}

void kbd_reset(void) {
  // nothing for the moment
}


#ifdef DEBUG
void  dump(uint8_t *buffer, size_t size) {
  uint32_t i, a, lsize;
  int c;

  for (a = 0;;) {
    printf("%08X: ", a);
    lsize = (size >= 16) ? 16 : size;
    for (i=0 ; i<lsize; i++)
      printf("%02X ", buffer[a + i]);
    for (i = lsize; i<16; i++)
      printf("   ");
    printf("  |");
    for (i=0;i<lsize;i++) {
      c = buffer[a+i];
      printf("%c", ((c < 0x20) || (c > 126)) ? '.' : c);
    }
    for (i=size;i<32;i++)
      printf(" ");
    a += lsize;
    size -= lsize;
    printf("|\n");
    if (size <= 0)
      return;
  }
}
#else
void  dump(uint8_t *buffer, size_t size) {
}
#endif

void process_keycode(int keycode, int modifier, bool is_break) {
#ifdef DEBUG
  printf("keycode: %04x, modified %04x %d\n", keycode, modifier, is_break);
#endif
  kbd_decode_trs80(krb, keycode, modifier, is_break);
}

bool led_service(repeating_timer_t *rt) {
  static bool led_state = false;
  board_led_write(led_state);
  led_state = !led_state;
  return true;
}

int main(void) {
  static struct repeating_timer timer_led;

  board_init();
#ifdef DEBUG
  stdio_uart_init_full(uart1, DEBUG_BAUD, DEBUG_TX_PIN, DEBUG_RX_PIN);
#endif
  kbd_init();
  krb = KbdRingBufferCreate();
  tusb_init();
  add_repeating_timer_ms(500, led_service, NULL, &timer_led);
#ifdef DEBUG
  printf("starting...\n");
#endif
  while (1) {
    uint16_t key;
    
    tuh_task();
    while (KbdGetKey(krb, &key)) {
      uint8_t ch;

      ch = key & 0xff;
      kbd_send(ch);
#ifdef DEBUG
      printf("-> %2x\n", ch);
#endif
    }
  }
  KbdRingBufferRelease(krb);
}
