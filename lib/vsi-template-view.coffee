{CompositeDisposable} = require 'atom'
_ = require 'underscore-plus'
{Range} = require 'atom'
TagFinder = require './tag-finder'

module.exports =
class BracketMatcherView
  constructor: (@editor, editorElement) ->
    @subscriptions = new CompositeDisposable
    @tagFinder = new TagFinder(@editor)
    @pairHighlighted = false
    @tagHighlighted = false

    @subscriptions.add @editor.getBuffer().onDidChangeText(@updateMatch)
    @subscriptions.add @editor.onDidChangeGrammar(@updateMatch)
    @subscriptions.add @editor.onDidChangeSelectionRange(@updateMatch)
    @subscriptions.add @editor.onDidAddCursor(@updateMatch)
    @subscriptions.add @editor.onDidRemoveCursor(@updateMatch)

    @subscriptions.add atom.commands.add editorElement, 'vsitemplate:go-to-matching-bracket', =>
      @goToMatchingPair()

    @subscriptions.add atom.commands.add editorElement, 'vsitemplate:go-to-enclosing-bracket', =>
      @goToEnclosingPair()

    @subscriptions.add atom.commands.add editorElement, 'vsitemplate:select-inside-brackets', =>
      @selectInsidePair()

    @subscriptions.add atom.commands.add editorElement, 'vsitemplate:close-tag', =>
      @closeTag()

    @subscriptions.add @editor.onDidDestroy @destroy

    @updateMatch()

  destroy: =>
    @subscriptions.dispose()

  updateMatch: =>
    if @pairHighlighted
      @editor.destroyMarker(@startMarker.id)
      @editor.destroyMarker(@endMarker.id)

    @pairHighlighted = false
    @tagHighlighted = false

    return unless @editor.getLastSelection().isEmpty()
    return if @editor.isFoldedAtCursorRow()

    if pair = @tagFinder.findMatchingTags()
      @startMarker = @createMarker(pair.startRange)
      @endMarker = @createMarker(pair.endRange)
      @pairHighlighted = true
      @tagHighlighted = true

  createMarker: (bufferRange) ->
    marker = @editor.markBufferRange(bufferRange)
    @editor.decorateMarker(marker, type: 'highlight', class: 'bracket-matcher', deprecatedRegionClass: 'bracket-matcher')
    marker

  goToMatchingPair: ->
    return @goToEnclosingPair() unless @pairHighlighted
    position = @editor.getCursorBufferPosition()

    if @tagHighlighted
      startRange = @startMarker.getBufferRange()
      tagLength = startRange.end.column - startRange.start.column
      endRange = @endMarker.getBufferRange()
      if startRange.compare(endRange) > 0
        [startRange, endRange] = [endRange, startRange]

      # include the <
      startRange = new Range(startRange.start.traverse([0, -1]), endRange.end.traverse([0, -1]))
      # include the </
      endRange = new Range(endRange.start.traverse([0, -2]), endRange.end.traverse([0, -2]))

      if position.isLessThan(endRange.start)
        tagCharacterOffset = position.column - startRange.start.column
        tagCharacterOffset++ if tagCharacterOffset > 0
        tagCharacterOffset = Math.min(tagCharacterOffset, tagLength + 2) # include </
        @editor.setCursorBufferPosition(endRange.start.traverse([0, tagCharacterOffset]))
      else
        tagCharacterOffset = position.column - endRange.start.column
        tagCharacterOffset-- if tagCharacterOffset > 1
        tagCharacterOffset = Math.min(tagCharacterOffset, tagLength + 1) # include <
        @editor.setCursorBufferPosition(startRange.start.traverse([0, tagCharacterOffset]))
    else
      previousPosition = position.traverse([0, -1])
      startPosition = @startMarker.getStartBufferPosition()
      endPosition = @endMarker.getStartBufferPosition()

      if position.isEqual(startPosition)
        @editor.setCursorBufferPosition(endPosition.traverse([0, 1]))
      else if previousPosition.isEqual(startPosition)
        @editor.setCursorBufferPosition(endPosition)
      else if position.isEqual(endPosition)
        @editor.setCursorBufferPosition(startPosition.traverse([0, 1]))
      else if previousPosition.isEqual(endPosition)
        @editor.setCursorBufferPosition(startPosition)

  goToEnclosingPair: ->
    return if @pairHighlighted

    if pair = @tagFinder.findEnclosingTags()
      {startRange, endRange} = pair
      if startRange.compare(endRange) > 0
        [startRange, endRange] = [endRange, startRange]
      @editor.setCursorBufferPosition(pair.startRange.start)

  selectInsidePair: ->
    if @pairHighlighted
      startRange = @startMarker.getBufferRange()
      endRange = @endMarker.getBufferRange()

      if startRange.compare(endRange) > 0
        [startRange, endRange] = [endRange, startRange]

      if @tagHighlighted
        startPosition = startRange.end
        endPosition = endRange.start.traverse([0, -2]) # Don't select </
      else
        startPosition = startRange.start
        endPosition = endRange.start
    else if pair = @tagFinder.findEnclosingTags()
      {startRange, endRange} = pair
      if startRange.compare(endRange) > 0
        [startRange, endRange] = [endRange, startRange]
      startPosition = startRange.end
      endPosition = endRange.start.traverse([0, -2]) # Don't select </

    if startPosition? and endPosition?
      rangeToSelect = new Range(startPosition.traverse([0, 1]), endPosition)
      @editor.setSelectedBufferRange(rangeToSelect)

  # Insert at the current cursor position a closing tag if there exists an
  # open tag that is not closed afterwards.
  closeTag: ->
    cursorPosition = @editor.getCursorBufferPosition()
    preFragment = @editor.getTextInBufferRange([[0, 0], cursorPosition])
    postFragment = @editor.getTextInBufferRange([cursorPosition, [Infinity, Infinity]])

    if tag = @tagFinder.closingTagForFragments(preFragment, postFragment)
      @editor.insertText("{{/#{tag}}}")
