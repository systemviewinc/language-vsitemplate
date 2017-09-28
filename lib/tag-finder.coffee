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
      pattern = new RegExp("\\{\\{s*([?!~#]\\s*#{tagName})|(\\/\\s*#{tagName})\\s*\\}\\}", 'gi')
    else
      pattern = /\{\{(?:((?:for|if|not|contains)\s*[^}]*)|(end)|((?:else|else if)\s*[^}]*))\s*\}\}/gi
    pattern

  isTagRange: (range) ->
    scopes = @editor.scopeDescriptorForBufferPosition(range.start).getScopesArray()
    @tagSelector.matches(scopes)

  isCursorOnTag: ->
    @tagSelector.matches(@editor.getLastCursor().getScopeDescriptor().getScopesArray())

  findStartTags: (operator, tagName, endPosition) ->
    scanRange = new Range([0, 0], endPosition)
    pattern = @patternForTagName(operator, tagName)
    startRange = null
    unpairedCount = 0
    midRanges = []
    @editor.backwardsScanInBufferRange pattern, scanRange, ({match, range, stop}) =>
      if match[3]
        midRanges.push(range.translate([0, 2], [0, -2])) if unpairedCount == 0
      else if match[1]
        unpairedCount--
        if unpairedCount < 0
          startRange = range.translate([0, 2], [0, -2]) # Subtract {{ and block operator from range
          stop()
      else
        unpairedCount++

    {range: startRange, midRanges}

  findEndTags: (operator, tagName, startPosition) ->
    scanRange = new Range(startPosition, @editor.buffer.getEndPosition())
    pattern = @patternForTagName(operator, tagName)
    endRange = null
    unpairedCount = 0
    midRanges = []
    @editor.scanInBufferRange pattern, scanRange, ({match, range, stop}) =>
      if match[3]
        midRanges.push(range.translate([0, 2], [0, -2])) if unpairedCount == 0
      else if match[1]
        unpairedCount++
      else
        unpairedCount--
        if unpairedCount < 0
          endRange = range.translate([0, 2], [0, -2]) # Subtract {{/ and }} from range
          stop()

    {range: endRange, midRanges}

  findTags: ->
    ranges = null
    endPosition = @editor.getLastCursor().getCurrentWordBufferRange({@wordRegex}).end
    @editor.backwardsScanInBufferRange @tagPattern, [[0, 0], endPosition], ({match, range, stop}) =>
      stop()

      [entireMatch, prefix, operator, tagName, suffix] = match
      tag = tagName + suffix

      if range.start.row is range.end.row
        cursorRange = range.translate([0, prefix.length], [0, -suffix.length])
      else
        cursorRange = Range.fromObject([range.start.translate([0, prefix.length + operator.length]), [range.start.row, Infinity]])

      startTags = {range: cursorRange, midRanges: []}

      if operator == '/' || operator == 'end'
        endTags = @findStartTags(operator, tag, cursorRange.start)
      else if operator == 'else' || operator == 'else if'
        startTags = @findStartTags(operator, tag, cursorRange.start)
        endTags = @findEndTags(operator, tag, cursorRange.end)
      else
        endTags = @findEndTags(operator, tag, cursorRange.end)

      if endTags.range
        ranges = {
          startRange: startTags.range,
          endRange: endTags.range,
          midRanges: startTags.midRanges.concat endTags.midRanges
        }
      ranges.midRanges.push cursorRange if operator == 'else' || operator == 'else if'

    ranges

  findEnclosingTags: ->
    if ranges = @findStartEndTags()
      if @isTagRange(ranges.startRange) and @isTagRange(ranges.endRange)
        return ranges

    null

  findMatchingTags: ->
    @findTags() if @isCursorOnTag()
