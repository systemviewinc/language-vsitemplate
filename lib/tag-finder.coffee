{Range} = require 'atom'
_ = require 'underscore-plus'
SelectorCache = require './selector-cache'

# Helper to find the matching start/end tag for the start/end tag under the
# cursor in XML, HTML, etc. editors.
module.exports =
class TagFinder
  constructor: (@editor) ->
    @tagPattern = /(\{\{(\/?))([^\s\}\}]+)([\s\}\}]|$)/
    @wordRegex = /[-\w]*/
    @tagSelector = SelectorCache.get('meta.tag | punctuation.definition.tag')

  patternForTagName: (tagName) ->
    tagName = _.escapeRegExp(tagName)
    new RegExp("(\\{\\{#{tagName}([\\s\\}\\}]|$))|(\\{\\{/#{tagName}\\}\\})", 'gi')

  isTagRange: (range) ->
    scopes = @editor.scopeDescriptorForBufferPosition(range.start).getScopesArray()
    @tagSelector.matches(scopes)

  isCursorOnTag: ->
    @tagSelector.matches(@editor.getLastCursor().getScopeDescriptor().getScopesArray())

  findStartTag: (tagName, endPosition) ->
    scanRange = new Range([0, 0], endPosition)
    pattern = @patternForTagName(tagName)
    startRange = null
    unpairedCount = 0
    @editor.backwardsScanInBufferRange pattern, scanRange, ({match, range, stop}) =>

      if match[1]
        unpairedCount--
        if unpairedCount < 0
          startRange = range.translate([0, 1], [0, -match[2].length]) # Subtract < and tag name suffix from range
          stop()
      else
        unpairedCount++

    startRange

  findEndTag: (tagName, startPosition) ->
    scanRange = new Range(startPosition, @editor.buffer.getEndPosition())
    pattern = @patternForTagName(tagName)
    endRange = null
    unpairedCount = 0
    @editor.scanInBufferRange pattern, scanRange, ({match, range, stop}) =>

      if match[1]
        unpairedCount++
      else
        unpairedCount--
        if unpairedCount < 0
          endRange = range.translate([0, 2], [0, -1]) # Subtract </ and > from range
          stop()

    endRange

  findStartEndTags: ->
    ranges = null
    endPosition = @editor.getLastCursor().getCurrentWordBufferRange({@wordRegex}).end
    @editor.backwardsScanInBufferRange @tagPattern, [[0, 0], endPosition], ({match, range, stop}) =>
      stop()

      [entireMatch, prefix, isClosingTag, tagName, suffix] = match

      if range.start.row is range.end.row
        startRange = range.translate([0, prefix.length], [0, -suffix.length])
      else
        startRange = Range.fromObject([range.start.translate([0, prefix.length]), [range.start.row, Infinity]])

      if isClosingTag
        endRange = @findStartTag(tagName, startRange.start)
      else
        endRange = @findEndTag(tagName, startRange.end)

      ranges = {startRange, endRange} if startRange? and endRange?
    ranges

  findEnclosingTags: ->
    if ranges = @findStartEndTags()
      if @isTagRange(ranges.startRange) and @isTagRange(ranges.endRange)
        return ranges

    null

  findMatchingTags: ->
    @findStartEndTags() if @isCursorOnTag()
