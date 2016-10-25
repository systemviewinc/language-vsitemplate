BracketMatcherView = null

module.exports =
  activate: ->
    atom.workspace.observeTextEditors (editor) ->
      editorElement = atom.views.getView(editor)

      BracketMatcherView ?= require './vsi-template-view'
      new BracketMatcherView(editor, editorElement)
