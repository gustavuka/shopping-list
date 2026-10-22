/**
 * Haptics per docs/design-system.md#haptics, as far as the web allows: `navigator.vibrate` on
 * Android; on iPhone (no Vibration API) Safari 18+ ticks when a `<input switch>` toggles, so we
 * toggle a hidden one. Light patterns only; never for remote (partner) changes.
 */
export type Haptic = 'light' | 'success' | 'rigid' | 'selection' | 'error'

const patterns: Record<Haptic, number | number[]> = {
  light: 8,
  success: [10, 60, 14],
  rigid: 14,
  selection: 5,
  error: [20, 40, 20, 40, 20],
}

let iosSwitch: HTMLLabelElement | undefined

export function haptic(kind: Haptic): void {
  if ('vibrate' in navigator) {
    navigator.vibrate(patterns[kind])
    return
  }
  iosSwitch ??= makeIOSSwitch()
  iosSwitch.click()
  if (kind === 'success' || kind === 'error') setTimeout(() => iosSwitch?.click(), 90)
}

function makeIOSSwitch(): HTMLLabelElement {
  const label = document.createElement('label')
  label.ariaHidden = 'true'
  label.style.cssText = 'position:fixed;width:0;height:0;overflow:hidden;opacity:0;pointer-events:none'
  const input = document.createElement('input')
  input.type = 'checkbox'
  input.setAttribute('switch', '')
  input.tabIndex = -1
  label.append(input)
  document.body.append(label)
  return label
}
