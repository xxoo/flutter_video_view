// this file is ported from https://github.com/androidx/media/blob/release/libraries/ui/src/main/java/androidx/media3/ui/SubtitlePainter.java
/*
 * Copyright (C) 2016 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package dev.xx.video_view

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Paint.Join
import android.graphics.Paint.Style
import android.graphics.Rect
import android.text.BidiFormatter
import android.text.Layout.Alignment
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.AbsoluteSizeSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.util.DisplayMetrics
import androidx.core.content.withStyledAttributes
import androidx.core.graphics.withTranslation
import androidx.media3.common.text.Cue
import androidx.media3.common.util.Log
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.SubtitleView
import com.google.common.base.Joiner
import com.google.common.base.Splitter
import java.util.Arrays
import java.util.Objects
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Paints subtitle {@link Cue}s. */
@UnstableApi
class SubtitlePainter(context: Context) {

	private val tag = "SubtitlePainter"

	/** Ratio of inner padding to font size. */
	private val innerPaddingRatio = 0.125f

	// Styled dimensions.
	private val outlineWidth: Float
	private val shadowRadius: Float
	private val shadowOffset: Float
	private var spacingMulti = 0f
	private var spacingAdd = 0f

	private val textPaint: TextPaint
	private val windowPaint: Paint
	private val bitmapPaint: Paint

	// Previous input variables.
	private var cueText: CharSequence? = null
	private var cueTextAlignment: Alignment? = null
	private var cueBitmap: Bitmap? = null
	private var cueLine = 0f
	private var cueLineType = 0
	private var cueLineAnchor = 0
	private var cuePosition = 0f
	private var cuePositionAnchor = 0
	private var cueSize = 0f
	private var cueBitmapHeight = 0f
	private var foregroundColor = 0
	private var backgroundColor = 0
	private var windowColor = 0
	private var edgeColor = 0
	private var edgeType = 0
	private var defaultTextSizePx = 0f
	private var cueTextSizePx = 0f
	private var bottomPaddingFraction = 0f
	private var parentLeft = 0
	private var parentTop = 0
	private var parentRight = 0
	private var parentBottom = 0

	// Derived drawing variables.
	private var textLayout: StaticLayout? = null
	private var edgeLayout: StaticLayout? = null
	private var textLeft: Int = 0
	private var textTop: Int = 0
	private var textPaddingX: Int = 0
	private var bitmapRect: Rect? = null

	init {
		val viewAttr = intArrayOf(android.R.attr.lineSpacingExtra, android.R.attr.lineSpacingMultiplier)
		context.withStyledAttributes(null, viewAttr, 0, 0) {
			spacingAdd = getDimensionPixelSize(0, 0).toFloat()
			@SuppressWarnings("ResourceType")
			spacingMulti = getFloat(1, 1f)
		}

		val resources = context.resources
		val displayMetrics = resources.displayMetrics
		val twoDpInPx = ((2f * displayMetrics.densityDpi) / DisplayMetrics.DENSITY_DEFAULT).roundToInt()
			.toFloat()
		outlineWidth = twoDpInPx
		shadowRadius = twoDpInPx
		shadowOffset = twoDpInPx

		textPaint = TextPaint()
		textPaint.isAntiAlias = true
		textPaint.isSubpixelText = true

		windowPaint = Paint()
		windowPaint.isAntiAlias = true
		windowPaint.style = Style.FILL

		bitmapPaint = Paint()
		bitmapPaint.isAntiAlias = true
		bitmapPaint.isFilterBitmap = true
	}

	/**
	 * Draws the provided {@link Cue} into a canvas with the specified styling.
	 *
	 * <p>A call to this method is able to use cached results of calculations made during the previous
	 * call, and so an instance of this class is able to optimize repeated calls to this method in
	 * which the same parameters are passed.
	 *
	 * @param cue The cue to draw. sizes embedded within the cue should be applied. Otherwise, it is
	 *     ignored.
	 * @param canvas The canvas into which to draw.
	 */
	fun draw(cue: Cue, canvas: Canvas) {
		val cue = if (cue.verticalType == Cue.TYPE_UNSET) cue else SubtitleViewUtils.repositionVerticalCue(cue)
		val isTextCue = cue.bitmap == null
		var windowColor = Color.BLACK
		val style = CaptionStyleCompat.DEFAULT
		val bottomPaddingFraction = SubtitleView.DEFAULT_BOTTOM_PADDING_FRACTION
		val cueBoxTop = 0
		val cueBoxBottom = canvas.height - (canvas.height * bottomPaddingFraction).roundToInt()
		val cueBoxLeft = 0
		val cueBoxRight = canvas.width
		val defaultTextSizePx = SubtitleViewUtils.resolveTextSize(Cue.TEXT_SIZE_TYPE_FRACTIONAL, SubtitleView.DEFAULT_TEXT_SIZE_FRACTION, canvas.height, cueBoxBottom - cueBoxTop)
		val cueTextSizePx = SubtitleViewUtils.resolveTextSize(Cue.TEXT_SIZE_TYPE_FRACTIONAL, cue.textSize, canvas.height, cueBoxBottom - cueBoxTop)
		if (isTextCue) {
			if (TextUtils.isEmpty(cue.text)) {
				// Nothing to draw.
				return
			}
			windowColor = if (cue.windowColorSet) cue.windowColor else style.windowColor
		}
		if (this.cueText == cue.text
			&& Objects.equals(this.cueTextAlignment, cue.textAlignment)
			&& this.cueBitmap == cue.bitmap
			&& this.cueLine == cue.line
			&& this.cueLineType == cue.lineType
			&& Objects.equals(this.cueLineAnchor, cue.lineAnchor)
			&& this.cuePosition == cue.position
			&& Objects.equals(this.cuePositionAnchor, cue.positionAnchor)
			&& this.cueSize == cue.size
			&& this.cueBitmapHeight == cue.bitmapHeight
			&& this.foregroundColor == style.foregroundColor
			&& this.backgroundColor == style.backgroundColor
			&& this.windowColor == windowColor
			&& this.edgeType == style.edgeType
			&& this.edgeColor == style.edgeColor
			&& Objects.equals(this.textPaint.typeface, style.typeface)
			&& this.defaultTextSizePx == defaultTextSizePx
			&& this.cueTextSizePx == cueTextSizePx
			&& this.bottomPaddingFraction == bottomPaddingFraction
			&& this.parentLeft == cueBoxLeft
			&& this.parentTop == cueBoxTop
			&& this.parentRight == cueBoxRight
			&& this.parentBottom == cueBoxBottom
		) {
			// We can use the cached layout.
			drawLayout(canvas, isTextCue)
			return
		}

		this.cueText = if (BidiUtils.containsRtl(cue.text)) BidiUtils.wrapText(cue.text!!) else cue.text
		this.cueTextAlignment = cue.textAlignment
		this.cueBitmap = cue.bitmap
		this.cueLine = cue.line
		this.cueLineType = cue.lineType
		this.cueLineAnchor = cue.lineAnchor
		this.cuePosition = cue.position
		this.cuePositionAnchor = cue.positionAnchor
		this.cueSize = cue.size
		this.cueBitmapHeight = cue.bitmapHeight
		this.foregroundColor = style.foregroundColor
		this.backgroundColor = style.backgroundColor
		this.windowColor = windowColor
		this.edgeType = style.edgeType
		this.edgeColor = style.edgeColor
		this.textPaint.typeface = style.typeface
		this.defaultTextSizePx = defaultTextSizePx
		this.cueTextSizePx = cueTextSizePx
		this.bottomPaddingFraction = bottomPaddingFraction
		this.parentLeft = cueBoxLeft
		this.parentTop = cueBoxTop
		this.parentRight = cueBoxRight
		this.parentBottom = cueBoxBottom

		if (isTextCue) {
			setupTextLayout()
		} else {
			setupBitmapLayout()
		}
		drawLayout(canvas, isTextCue)
	}

	private fun setupTextLayout() {
		val cueText = if (this.cueText is SpannableStringBuilder) {
			this.cueText as SpannableStringBuilder
		} else {
			SpannableStringBuilder(this.cueText)
		}
		val parentWidth = parentRight - parentLeft
		val parentHeight = parentBottom - parentTop

		textPaint.textSize = defaultTextSizePx
		val textPaddingX = (defaultTextSizePx * innerPaddingRatio + 0.5f).toInt()

		var availableWidth = parentWidth - textPaddingX * 2
		if (cueSize != Cue.DIMEN_UNSET) {
			availableWidth = (availableWidth * cueSize).toInt()
		}
		if (availableWidth <= 0) {
			Log.w(tag, "Skipped drawing subtitle cue (insufficient space)")
			return
		}

		if (cueTextSizePx > 0) {
			// Use an AbsoluteSizeSpan encompassing the whole text to apply the default cueTextSizePx.
			cueText.setSpan(
				AbsoluteSizeSpan((cueTextSizePx).toInt()),
				/* start= */ 0,
				/* end= */ cueText.length,
				Spanned.SPAN_PRIORITY
			)
		}

		// Remove embedded font color to not destroy edges, otherwise it overrides edge color.
		val cueTextEdge = SpannableStringBuilder(cueText)
		if (edgeType == CaptionStyleCompat.EDGE_TYPE_OUTLINE) {
			cueTextEdge.getSpans(0, cueTextEdge.length, ForegroundColorSpan::class.java)
				.forEach { cueTextEdge.removeSpan(it) }
		}

		// EDGE_TYPE_NONE & EDGE_TYPE_DROP_SHADOW both paint in one pass, they ignore cueTextEdge.
		// In other cases we use two painters and we need to apply the background in the first one only,
		// otherwise the background color gets drawn in front of the edge color
		// (https://github.com/google/ExoPlayer/pull/6724#issuecomment-564650572).
		if (Color.alpha(backgroundColor) > 0) {
			if (edgeType == CaptionStyleCompat.EDGE_TYPE_NONE
				|| edgeType == CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW) {
				cueText.setSpan(
					BackgroundColorSpan(backgroundColor), 0, cueText.length, Spanned.SPAN_PRIORITY
				)
			} else {
				cueTextEdge.setSpan(
					BackgroundColorSpan(backgroundColor),
					0,
					cueTextEdge.length,
					Spanned.SPAN_PRIORITY
				)
			}
		}

		val textAlignment = if (cueTextAlignment == null) {
			Alignment.ALIGN_CENTER
		} else {
			cueTextAlignment!!
		}
		val textLayout = StaticLayout.Builder.obtain(cueText, 0, cueText.length, textPaint, availableWidth)
			.setAlignment(textAlignment)
			.setLineSpacing(spacingAdd, spacingMulti)
			.setIncludePad(true)
			.build()
		val textHeight = textLayout.height
		var textWidth = 0
		val lineCount = textLayout.lineCount
		for (i in 0 until lineCount) {
			textWidth = ceil(textLayout.getLineWidth(i).toDouble()).toInt().coerceAtLeast(textWidth)
		}
		if (cueSize != Cue.DIMEN_UNSET && textWidth < availableWidth) {
			textWidth = availableWidth
		}
		textWidth += textPaddingX * 2

		var textLeft: Int
		var textRight: Int
		if (cuePosition != Cue.DIMEN_UNSET) {
			val anchorPosition = (parentWidth * cuePosition).roundToInt() + parentLeft
			textLeft = when (cuePositionAnchor) {
				Cue.ANCHOR_TYPE_END -> {
					anchorPosition - textWidth
				}
				Cue.ANCHOR_TYPE_MIDDLE -> {
					(anchorPosition * 2 - textWidth) / 2
				}
				Cue.ANCHOR_TYPE_START, Cue.TYPE_UNSET -> {
					anchorPosition
				}
				else -> {
					anchorPosition
				}
			}

			textLeft = textLeft.coerceAtLeast(parentLeft)
			textRight = (textLeft + textWidth).coerceAtMost(parentRight)
		} else {
			textLeft = (parentWidth - textWidth) / 2 + parentLeft
			textRight = textLeft + textWidth
		}

		textWidth = textRight - textLeft
		if (textWidth <= 0) {
			Log.w(tag, "Skipped drawing subtitle cue (invalid horizontal positioning)")
			return
		}

		var textTop: Int
		if (cueLine != Cue.DIMEN_UNSET) {
			if (cueLineType == Cue.LINE_TYPE_FRACTION) {
				val anchorPosition = (parentHeight * cueLine).roundToInt() + parentTop
				textTop = when (cueLineAnchor) {
					Cue.ANCHOR_TYPE_END -> anchorPosition - textHeight
					Cue.ANCHOR_TYPE_MIDDLE -> (anchorPosition * 2 - textHeight) / 2
					else -> anchorPosition
				}
			} else {
				// cueLineType == Cue.LINE_TYPE_NUMBER
				val firstLineHeight = textLayout.getLineBottom(0) - textLayout.getLineTop(0)
				textTop = if (cueLine >= 0) {
					(cueLine * firstLineHeight).roundToInt() + parentTop
				} else {
					((cueLine + 1) * firstLineHeight).roundToInt() + parentBottom - textHeight
				}
			}

			if (textTop + textHeight > parentBottom) {
				textTop = parentBottom - textHeight
			} else if (textTop < parentTop) {
				textTop = parentTop
			}
		} else {
			textTop = parentBottom - textHeight - (parentHeight * bottomPaddingFraction).toInt()
		}

		// Update the derived drawing variables.
		this.textLayout = StaticLayout.Builder.obtain(cueText, 0, cueText.length, textPaint, textWidth)
			.setAlignment(textAlignment)
			.setLineSpacing(spacingAdd, spacingMulti)
			.setIncludePad(true)
			.build()
		this.edgeLayout = StaticLayout.Builder.obtain(cueTextEdge, 0, cueText.length, textPaint, textWidth)
			.setAlignment(textAlignment)
			.setLineSpacing(spacingAdd, spacingMulti)
			.setIncludePad(true)
			.build()
		this.textLeft = textLeft
		this.textTop = textTop
		this.textPaddingX = textPaddingX
	}

	private fun setupBitmapLayout() {
		val cueBitmap = this.cueBitmap!!
		val parentWidth = parentRight - parentLeft
		val parentHeight = parentBottom - parentTop
		val anchorX = parentLeft + (parentWidth * cuePosition)
		val anchorY = parentTop + (parentHeight * cueLine)
		val width = (parentWidth * cueSize).roundToInt()
		val height = if (cueBitmapHeight != Cue.DIMEN_UNSET) {
			(parentHeight * cueBitmapHeight).roundToInt()
		} else {
			(width * (cueBitmap.height.toFloat() / cueBitmap.width)).roundToInt()
		}
		val x = when (cuePositionAnchor) {
			Cue.ANCHOR_TYPE_END -> (anchorX - width)
			Cue.ANCHOR_TYPE_MIDDLE -> (anchorX - (width / 2))
			else -> anchorX
		}.roundToInt()
		val y = when (cueLineAnchor) {
			Cue.ANCHOR_TYPE_END -> (anchorY - height)
			Cue.ANCHOR_TYPE_MIDDLE -> (anchorY - (height / 2))
			else -> anchorY
		}.roundToInt()
		bitmapRect = Rect(x, y, x + width, y + height)
	}

	private fun drawLayout(canvas: Canvas, isTextCue: Boolean) {
		if (isTextCue) {
			drawTextLayout(canvas)
		} else {
			drawBitmapLayout(canvas)
		}
	}

	private fun drawTextLayout(canvas: Canvas) {
		val textLayout = this.textLayout
		val edgeLayout = this.edgeLayout
		if (textLayout == null || edgeLayout == null) {
			// Nothing to draw.
			return
		}

		canvas.withTranslation(textLeft.toFloat(), textTop.toFloat()) {
			if (Color.alpha(windowColor) > 0) {
				windowPaint.color = windowColor
				canvas.drawRect(
					-textPaddingX.toFloat(),
					0f,
					textLayout.width + textPaddingX.toFloat(),
					textLayout.height.toFloat(),
					windowPaint
				)
			}

			when (edgeType) {
				CaptionStyleCompat.EDGE_TYPE_OUTLINE -> {
					textPaint.strokeJoin = Join.ROUND
					textPaint.strokeWidth = outlineWidth
					textPaint.color = edgeColor
					textPaint.style = Style.FILL_AND_STROKE
					edgeLayout.draw(canvas)
				}
				CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW -> {
					textPaint.setShadowLayer(shadowRadius, shadowOffset, shadowOffset, edgeColor)
				}
				CaptionStyleCompat.EDGE_TYPE_RAISED, CaptionStyleCompat.EDGE_TYPE_DEPRESSED -> {
					val raised = edgeType == CaptionStyleCompat.EDGE_TYPE_RAISED
					val colorUp = if (raised) Color.WHITE else edgeColor
					val colorDown = if (raised) edgeColor else Color.WHITE
					val offset = shadowRadius / 2f
					textPaint.color = foregroundColor
					textPaint.style = Style.FILL
					textPaint.setShadowLayer(shadowRadius, -offset, -offset, colorUp)
					edgeLayout.draw(canvas)
					textPaint.setShadowLayer(shadowRadius, offset, offset, colorDown)
				}
			}

			textPaint.color = foregroundColor
			textPaint.style = Style.FILL
			textLayout.draw(canvas)
			textPaint.setShadowLayer(0f, 0f, 0f, 0)
		}
	}

	private fun drawBitmapLayout(canvas: Canvas) {
		canvas.drawBitmap(cueBitmap!!, /* src= */ null, bitmapRect!!, bitmapPaint)
	}
}

/** Utility class for subtitle layout logic. */
@UnstableApi
object SubtitleViewUtils {

	/**
	 * Returns the text size in px, derived from [textSize] and [textSizeType].
	 *
	 * Returns [Cue.DIMEN_UNSET] if [textSize] == Cue.DIMEN_UNSET or [textSizeType] == Cue.TYPE_UNSET.
	 */
	fun resolveTextSize(
		@Cue.TextSizeType textSizeType: Int,
		textSize: Float,
		rawViewHeight: Int,
		viewHeightMinusPadding: Int
	): Float {
		if (textSize == Cue.DIMEN_UNSET) {
			return Cue.DIMEN_UNSET
		}
		return when (textSizeType) {
			Cue.TEXT_SIZE_TYPE_ABSOLUTE -> textSize
			Cue.TEXT_SIZE_TYPE_FRACTIONAL -> textSize * viewHeightMinusPadding
			Cue.TEXT_SIZE_TYPE_FRACTIONAL_IGNORE_PADDING -> textSize * rawViewHeight
			else -> Cue.DIMEN_UNSET
		}
	}

	fun repositionVerticalCue(cue: Cue): Cue {
		val cueBuilder = cue.buildUpon()
			.setPosition(Cue.DIMEN_UNSET)
			.setPositionAnchor(Cue.TYPE_UNSET)
			.setTextAlignment(null)

		if (cue.lineType == Cue.LINE_TYPE_FRACTION) {
			cueBuilder.setLine(1.0f - cue.line, Cue.LINE_TYPE_FRACTION)
		} else {
			cueBuilder.setLine(-cue.line - 1f, Cue.LINE_TYPE_NUMBER)
		}
		when (cue.lineAnchor) {
			Cue.ANCHOR_TYPE_END -> cueBuilder.setLineAnchor(Cue.ANCHOR_TYPE_START)
			Cue.ANCHOR_TYPE_START -> cueBuilder.setLineAnchor(Cue.ANCHOR_TYPE_END)
			Cue.ANCHOR_TYPE_MIDDLE, Cue.TYPE_UNSET -> {
				// Fall through
			}
		}
		return cueBuilder.build()
	}
}

/**
 * Utility class for handling bidirectional (BiDi) text rendering.
 *
 *
 * This class provides methods to check for right-to-left (RTL) characters in a text and to wrap
 * text lines for proper BiDi rendering using [BidiFormatter].
 */
@UnstableApi
internal object BidiUtils {
	private val LF_SPLITTER: Splitter = Splitter.on("\n")
	private val CRLF_SPLITTER: Splitter = Splitter.on("\r\n")
	private val LF_JOINER: Joiner = Joiner.on("\n")
	private const val TAG = "BidiUtils"

	/**
	 * Checks whether the given [CharSequence] contains any characters with right-to-left (RTL)
	 * directionality.
	 *
	 *
	 * This method inspects each character's Unicode directionality and returns `true` if at
	 * least one character is classified as RTL. This includes characters with the following
	 * directionalities:
	 *
	 *
	 *  * [Character.DIRECTIONALITY_RIGHT_TO_LEFT]
	 *  * [Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC]
	 *  * [Character.DIRECTIONALITY_RIGHT_TO_LEFT_EMBEDDING]
	 *  * [Character.DIRECTIONALITY_RIGHT_TO_LEFT_OVERRIDE]
	 *
	 *
	 * @param input the input [CharSequence] to analyze
	 * @return `true` if the input contains at least one RTL character; `false` otherwise
	 */
	@JvmStatic
	fun containsRtl(input: CharSequence?): Boolean {
		if (input == null) {
			return false
		}
		val length = input.length
		var offset = 0
		while (offset < length) {
			val codePoint = Character.codePointAt(input, offset)
			val dir = Character.getDirectionality(codePoint)
			if (dir == Character.DIRECTIONALITY_RIGHT_TO_LEFT || dir == Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC || dir == Character.DIRECTIONALITY_RIGHT_TO_LEFT_EMBEDDING || dir == Character.DIRECTIONALITY_RIGHT_TO_LEFT_OVERRIDE) {
				return true
			}
			offset += Character.charCount(codePoint)
		}
		return false
	}

	/**
	 * Applies bidirectional (BiDi) Unicode wrapping to each line of the given [CharSequence].
	 *
	 *
	 * This method ensures that text containing both left-to-right (LTR) and right-to-left (RTL)
	 * scripts is displayed correctly by wrapping each line using [BidiFormatter.unicodeWrap].
	 * It forces LTR context for wrapping and preserves spans and line breaks.
	 *
	 * @param input the input text as a [CharSequence], possibly containing mixed-direction text
	 * @return a [CharSequence] with each line wrapped for proper bidi rendering
	 */
	@JvmStatic
	fun wrapText(input: CharSequence): CharSequence {
		val bidiFormatter = BidiFormatter.getInstance()
		var spannedInput: Spanned? = null
		var spans: Array<Any>? = null
		var spanStarts: IntArray? = null
		var spanEnds: IntArray? = null

		if (input is Spanned) {
			// Preserve span in the input text.
			spannedInput = input
			spans = spannedInput.getSpans(0, input.length, Any::class.java)
			// Create arrays to track the start and end of each span after wrapping.
			spanStarts = IntArray(spans.size)
			spanEnds = IntArray(spans.size)
			Arrays.fill(spanStarts, -1)
			Arrays.fill(spanEnds, -1)
		}

		// Determine the end-of-line (EOL) sequence for splitting the input text.
		val lines: MutableList<String>?
		val eolLength: Int
		if (input.toString().contains("\r\n")) {
			lines = CRLF_SPLITTER.splitToList(input)
			eolLength = 2
		} else {
			lines = LF_SPLITTER.splitToList(input)
			eolLength = 1
		}

		val wrappedLines: MutableList<String> = ArrayList(lines.size)

		// Calculate the offset of each span after wrapping
		var spanUpdate = 0
		var lineStart = 0
		for (line in lines) {
			// According to unicodeWrap documentation, this will either add 2 more characters or none
			val wrappedLine = bidiFormatter.unicodeWrap(line, TextDirectionHeuristics.LTR)
			if (spans != null) {
				val diff = wrappedLine.length - line.length
				if (diff > 0) {
					spanUpdate++
				}
				for (j in spans.indices) {
					// Each span start or end is updated only once
					if ((spanStarts!![j] < 0)
						&& (spannedInput!!.getSpanStart(spans[j]) >= lineStart)
						&& (spannedInput.getSpanStart(spans[j]) < lineStart + line.length)
					) {
						spanStarts[j] = spanUpdate
					}
					if ((spanEnds!![j] < 0)
						&& ((spannedInput!!.getSpanEnd(spans[j]) - 1) >= lineStart)
						&& ((spannedInput.getSpanEnd(spans[j]) - 1) < lineStart + line.length)
					) {
						spanEnds[j] = spanUpdate
					}
				}
				lineStart += line.length + eolLength
				if (diff > 0) {
					spanUpdate++
				}
			}
			wrappedLines.add(wrappedLine)
		}

		// Create a new SpannableStringBuilder with the wrapped lines.
		val wrapped = SpannableStringBuilder(LF_JOINER.join(wrappedLines))

		if (spans != null) {
			// Reapply original spans to the wrapped lines.
			for (i in spans.indices) {
				val start = spannedInput!!.getSpanStart(spans[i]) + spanStarts!![i]
				val end = spannedInput.getSpanEnd(spans[i]) + spanEnds!![i]
				val flags = spannedInput.getSpanFlags(spans[i])
				if ((start >= 0) && (start < wrapped.length) && (end >= 0) && (end <= wrapped.length)) {
					// Only set the span if the start and end are within bounds of the wrapped text.
					wrapped.setSpan(spans[i], start, end, flags)
				} else {
					Log.w(
						TAG,
						"Span out of bounds: start=" + start + ",end=" + end + ",len=" + wrapped.length
					)
				}
			}
		}

		return wrapped
	}
}