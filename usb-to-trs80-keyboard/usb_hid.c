#include <stdio.h>
#include "pico/stdlib.h"
#include <stdlib.h>
#include <string.h>
#include "bsp/board.h"
#include "tusb.h"

#define HOTSPOT __inline__ __attribute__ ((always_inline, hot))

extern void process_keycode(uint8_t, uint8_t, bool is_break);
extern void dump(const uint8_t*, const size_t);
extern bool hid_debug;

static bool numlock_state     = false;
static bool capslock_state    = false;
static bool scrolllock_state  = false;
static bool first_report_seen = false;

void tuh_hid_mount_cb (uint8_t dev_addr, uint8_t instance, uint8_t const* desc_report, uint16_t desc_len) {
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);
  static bool initialized = false;
  static uint8_t leds;
  uint16_t vid, pid;
  
  if (hid_debug)
    printf("HID device address = %d, instance = %d is mounted\r\n", dev_addr, instance);
  tuh_vid_pid_get(dev_addr, &vid, &pid);

  if (hid_debug) {
    printf("VID = %04x, PID = %04x\r\n", vid, pid);
    printf("ITF PROTOCOL = %d\n", itf_protocol);
  }
  if (itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) {
    tuh_hid_receive_report (dev_addr, instance);
    if (hid_debug)
      printf("keyboard %0.4x %0.4x connected\n", vid, pid);      
    if (!initialized) {
      leds |= KEYBOARD_LED_NUMLOCK;
      tuh_hid_set_report(dev_addr, instance, 0, HID_REPORT_TYPE_OUTPUT, &leds, sizeof(leds));
      initialized = true;
    }
  }
}

HOTSPOT static bool key_pressed(hid_keyboard_report_t const *report, uint8_t keycode) {
  for (uint8_t i = 0; i < sizeof(report->keycode); i++) 
    if (report->keycode[i] == keycode) 
      return true;
  return false;
}

HOTSPOT static bool report_empty(hid_keyboard_report_t const *report, uint16_t len) {
  for (int i = 0; i < len; i++)
    if (report->keycode[i]) 
      return false;
  return true;
}

void tuh_hid_report_received_cb  (uint8_t dev_addr, uint8_t instance, uint8_t const* report, uint16_t len) {
  static hid_keyboard_report_t last_kbd_report = { 0, 0, { 0, 0, 0, 0, 0, 0 } };
  hid_keyboard_report_t *kbd_report;
  uint8_t button_mask;
  uint8_t i;
  (void) instance; (void) len;
  bool left, right, middle;
  static uint8_t leds = 0, last_leds = 0;
  
  switch (tuh_hid_interface_protocol (dev_addr, instance)) {
  case HID_ITF_PROTOCOL_KEYBOARD:
    kbd_report = (hid_keyboard_report_t *) report;

    if (hid_debug) {
      printf("kbd report len = %d\n", len);
      dump((const uint8_t *) kbd_report, sizeof(kbd_report));
    }

    /* PRESSES: in new report, not in previous — guarded by !report_empty */
    if (!report_empty(kbd_report, len)) {
      for (i = 0; i < sizeof(kbd_report->keycode); i++) {
	if (kbd_report->keycode[i] &&
	    !key_pressed(&last_kbd_report, kbd_report->keycode[i])) {
	  switch (kbd_report->keycode[i]) {
	  case 0x39:
	    capslock_state = !capslock_state;
	    if (capslock_state) leds |=  KEYBOARD_LED_CAPSLOCK;
	    else                leds &= ~KEYBOARD_LED_CAPSLOCK;
	    break;
	  case 0x47:
	    scrolllock_state = !scrolllock_state;
	    if (scrolllock_state) leds |=  KEYBOARD_LED_SCROLLLOCK;
	    else                  leds &= ~KEYBOARD_LED_SCROLLLOCK;
	    break;
	  case 0x53:
	    numlock_state = !numlock_state;
	    if (!numlock_state) leds |=  KEYBOARD_LED_NUMLOCK;
	    else                leds &= ~KEYBOARD_LED_NUMLOCK;
	    break;
	  default:
	    process_keycode(kbd_report->keycode[i],
			    kbd_report->modifier,
			    false);    /* press = make, is_break = false */
	    break;
	  }
	}
      }
    }
    
    /* RELEASES: in previous report, not in new — MUST run even when
       the new report is empty (all keys lifted).                      */
    for (i = 0; i < sizeof(last_kbd_report.keycode); i++) {
      uint8_t kc = last_kbd_report.keycode[i];
      if (!kc) continue;
      if (key_pressed(kbd_report, kc)) continue;  /* still held */
      
      switch (kc) {
      case 0x39: case 0x47: case 0x53:
	break;                        /* locks toggle on press only */
      default:
	process_keycode(kc, kbd_report->modifier, true);   /* release = break */
	break;
      }
    }
    
    if (last_leds != leds) {
      tuh_hid_set_report(dev_addr, instance, 0,
			 HID_REPORT_TYPE_OUTPUT, &leds, sizeof(leds));
      last_leds = leds;
    }
    memcpy(&last_kbd_report, kbd_report, sizeof(last_kbd_report));
    break;
  }
  tuh_hid_receive_report(dev_addr, instance);    /* always re-arm, outside switch */
}  

void tuh_hid_umount_cb (uint8_t dev_addr, uint8_t instance)  {
  uint8_t const itf_protocol = tuh_hid_interface_protocol(dev_addr, instance);
  uint16_t vid, pid;

  if (hid_debug) 
    printf("HID device address = %d, instance = %d is umounted\r\n", dev_addr, instance);
  tuh_vid_pid_get(dev_addr, &vid, &pid);
  
  if (itf_protocol == HID_ITF_PROTOCOL_KEYBOARD) {
    if (hid_debug) 
      printf("keyboard %0.4x %0.4x disconnected\n", vid, pid);  
  }
}

