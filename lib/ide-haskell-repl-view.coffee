SubAtom = require 'sub-atom'
{Range} = require 'atom'
GHCI = require './ghci'


module.exports =
class IdeHaskellReplView
  constructor: (@uri, @upi) ->
    # Create root element
    @disposables = new SubAtom

    # Create message element
    @element = document.createElement 'div'
    @element.classList.add('ide-haskell-repl')
    @element.appendChild @outputDiv = document.createElement 'div'
    @outputDiv.classList.add('ide-haskell-repl-output')
    @outputDiv.appendChild @outputElement =
      document.createElement('atom-text-editor')
    @outputElement.removeAttribute('tabindex')
    @output = @outputElement.getModel()
    @output.setSoftWrapped(true)
    @output.setLineNumberGutterVisible(false)
    @output.getDecorations(class: 'cursor-line', type: 'line')[0].destroy()
    @output.setGrammar \
      atom.grammars.grammarForScopeName 'text.tex.latex.haskell'
    unless @upi?
      @element.appendChild @errDiv = document.createElement 'div'
      @errDiv.classList.add 'ide-haskell-repl-error'
    @element.appendChild @promptDiv = document.createElement 'div'
    @element.appendChild @editorDiv = document.createElement 'div'
    @editorDiv.classList.add('ide-haskell-repl-editor')
    @editorDiv.appendChild @editorElement =
      document.createElement('atom-text-editor')
    @editorElement.classList.add 'ide-haskell-repl'
    @editor = @editorElement.getModel()
    @editor.setLineNumberGutterVisible(false)
    @editor.setGrammar \
      atom.grammars.grammarForScopeName 'source.haskell'

    @disposables.add atom.workspace.onDidChangeActivePaneItem (item) =>
      if item == @
        setTimeout =>
          @editorElement.focus()
        , 1

    @editorElement.onDidAttach =>
      @setEditorHeight()
    @editor.onDidChange =>
      @setEditorHeight()

    @editor.setText ''

    @output.onDidChange ({start, end}) =>
      @output.scrollToCursorPosition()

    @cwd = atom.project.getDirectories()[0]

    @ghci = new GHCI
      atomPath: process.execPath
      command: atom.config.get 'ide-haskell-repl.commandPath'
      args: atom.config.get 'ide-haskell-repl.commandArgs'
      cwd: @cwd.getPath()
      onResponse: (response) =>
        @log response
      onError: (error) =>
        @setError error
      onFinished: (prompt) =>
        @setPrompt prompt
      onExit: (code) =>
        atom.workspace.paneForItem(@)?.destroyItem?(@)

    @ghci.load(@uri) if @uri

  execCommand: ->
    if @ghci.writeLines @editor.getBuffer().getLines()
      @editor.setText ''

  historyBack: ->
    @editor.setText @ghci.historyBack(@editor.getText())

  historyForward: ->
    @editor.setText @ghci.historyForward()

  ghciReload: ->
    @ghci.writeLines [':reload']

  setEditorHeight: ->
    lh = @editor.getLineHeightInPixels()
    lines = @editor.getScreenLineCount()
    @editorDiv.style.setProperty 'height',
      "#{lines * lh}px"

  setPrompt: (prompt) ->
    @promptDiv.innerText = prompt + '>'

  setError: (err) ->
    if @errDiv?
      @errDiv.innerText = err
    else
      @upi.setMessages @splitErrBuffer err

  splitErrBuffer: (errBuffer) ->
    # Start of a Cabal message
    startOfMessage = /\n\S/
    som = errBuffer.search startOfMessage
    msgs = while som >= 0
      errMsg     = errBuffer.substr(0, som + 1)
      errBuffer = errBuffer.substr(som + 1)
      som        = errBuffer.search startOfMessage
      @parseMessage errMsg
    # Try to parse whatever is left in the buffer
    msgs.push @parseMessage errBuffer
    msgs.filter (msg) -> msg?

  unindentMessage: (message) ->
    lines = message.split('\n')
    minIndent = null
    for line in lines
      match = line.match /^[\t\s]*/
      lineIndent = match[0].length
      minIndent = lineIndent if lineIndent < minIndent or not minIndent?
    if minIndent?
      lines = for line in lines
        line.slice(minIndent)
    lines.join('\n')


  parseMessage: (raw) ->
    # Regular expression to match against a location in a cabal msg (Foo.hs:3:2)
    # The [^] syntax basically means "anything at all" (including newlines)
    matchLoc = /(\S+):(\d+):(\d+):( Warning:)?\n?([^]*)/
    if raw.trim() != ""
      matched = raw.match(matchLoc)
      if matched?
        [file, line, col, rawTyp, msg] = matched.slice(1, 6)
        typ = if rawTyp? then "warning" else "error"
        if file is '<interactive>'
          file = undefined
          typ = 'repl'

        uri: if file? then @cwd.getFile(@cwd.relativize(file)).getPath()
        position: [parseInt(line) - 1, parseInt(col) - 1]
        message: @unindentMessage(msg.trimRight())
        severity: typ
      else
        message: raw
        severity: 'repl'

  log: (text) ->
    eofRange = Range.fromPointWithDelta(@output.getEofBufferPosition(), 0, 0)
    @output.setTextInBufferRange eofRange, text
    @lastPos = @output.getEofBufferPosition()

  getURI: ->
    "ide-haskell://repl/#{@uri}"

  getTitle: ->
    "REPL: #{@uri}"

  destroy: ->
    @ghci.destroy()
    @element.remove()
    @disposables.dispose()
