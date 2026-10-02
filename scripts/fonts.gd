class_name Fonts
## 同梱フォント（16.2）。Courier Prime は日本語の字形を持たないので、足りない字は BIZ UDPGothic で出す。

const DELA: Font = preload("res://assets/fonts/DelaGothicOne-Regular.ttf")  # 見出し・ボタン・大きい数字・演出文字
const BIZ: Font = preload("res://assets/fonts/BIZUDPGothic-Regular.ttf")  # 本文・説明・ラベル
const BIZ_BOLD: Font = preload("res://assets/fonts/BIZUDPGothic-Bold.ttf")
## 英字ラベル・キー表示・報告書の数値
static var courier: Font = _with_fallback(preload("res://assets/fonts/CourierPrime-Regular.ttf"), BIZ)
static var courier_bold: Font = _with_fallback(preload("res://assets/fonts/CourierPrime-Bold.ttf"), BIZ_BOLD)


static func _with_fallback(base: Font, fallback: Font) -> Font:
	var f := FontVariation.new()
	f.base_font = base
	f.fallbacks = [fallback]
	return f
