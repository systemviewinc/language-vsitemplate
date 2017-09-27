{Range} = require 'atom'
_ = require 'underscore-plus'
SelectorCache = require './selector-cache'

# Helper to find the matching start/end tag for the start/end tag under the
# cursor in XML, HTML, etc. editors.
module.exports =
class TagFinder
  constructor: (@editor) ->
    @tagPattern = /(\{\{)([\?\!/~#]|for|end|if|else|else if|not|contains)\s*([^}]*)(@?)/
    @wordRegex = /[^\}\r\n]*/
    @tagSelector = SelectorCache.get('block.vsitemplate')

  patternForTagName: (operator, tagName) ->
    tagName = _.escapeRegExp(tagName)
    if operator.match(/[#!~?/]/)
      pattern = new RegExp("(\\{\\{[?!~#]\\s*#{tagName}\\s*\\}\\})|(\\{\\{\\s*/\\s*#{tagName}\\s*\\}\\})", 'gi')
    else
      pattern = /(\{\{(?:for|if|else|else if|not|contains)\s*[^}]*\}\})|(\{\{\s*end\s*\}\})/gi
    pattern

  isTagRange: (range) ->
    scopes = @editor.scopeDescriptorForBufferPosition(range.start).getScopesArray()
    @tagSelector.matches(scopes)

  isCursorOnTag: ->
    @tagSelector.matches(@editor.getLastCursor().getScopeDescriptor().getScopesArray())

  findStartTag: (operator, tagName, endPosition) ->
    scanRange = new Range([0, 0], endPosition)
    pattern = @patternForTagName(operator, tagName)
    startRange = null
    unpairedCount = 0
    @editor.backwardsScanInBufferRange pattern, scanRange, ({match, range, stop}) =>
      if match[1]
        unpairedCount--
        if unpairedCount < 0
          startRange = range.translate([0, 3], [0, -2]) # Subtract {{ and block operator from range
          stop()
      else
        unpairedCount++

    startRange

  findEndTag: (operator, tagName, startPosition) ->
    scanRange = new Range(startPosition, @editor.buffer.getEndPosition())
    pattern = @patternForTagName(operator, tagName)
    endRange = null
    unpairedCount = 0
    @editor.scanInBufferRange pattern, scanRange, ({match, range, stop}) =>
      if match[1]
        unpairedCount++
      else
        unpairedCount--
        if unpairedCount < 0
          endRange = range.translate([0, 3], [0, -2]) # Subtract {{/ and }} from range
          stop()

    endRange

  findStartEndTags: ->
    ranges = null
    endPosition = @editor.getLastCursor().getCurrentWordBufferRange({@wordRegex}).end
    @editor.backwardsScanInBufferRange @tagPattern, [[0, 0], endPosition], ({match, range, stop}) =>
      stop()

      [entireMatch, prefix, operator, tagName, suffix] = match
      tag = tagName + suffix

      if range.start.row is range.end.row
        startRange = range.translate([0, prefix.length + operator.length], [0, -suffix.length])
      else
        startRange = Range.fromObject([range.start.translate([0, prefix.length + operator.length]), [range.start.row, Infinity]])

      if operator == '/' || operator == 'end'
        endRange = @findStartTag(operator, tag, startRange.start)
      else
        endRange = @findEndTag(operator, tag, startRange.end)

      ranges = {startRange, endRange} if startRange? and endRange?
    ranges

  findEnclosingTags: ->
    if ranges = @findStartEndTags()
      if @isTagRange(ranges.startRange) and @isTagRange(ranges.endRange)
        return ranges

    null

  findMatchingTags: ->
    @findStartEndTags() if @isCursorOnTag()
