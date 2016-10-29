{Emitter}  = require 'atom'
inkTooltip = require './tooltip'

# Progress Bars
#
# This module provides an API for displaying progress bars in Atom. The methods
# below allow modifing the stack of progress bars, which is represented by
# corresponding UI elements:
#    - A "global" progress bar is shown in the status bar. In pratice, this is
#      the first determinate progress bar in the stack. If there is none, the
#      first element (which then is indeterminate) will be shown instead. If the
#      stack is empty, an empty progress bar will be shown instead.
#    - Hovering over that status bar element will show the complete stack as
#      an overlay.
#    - Hovering over the actual progress bar of one such stack element will show
#      the message correesponding to that progress bar, if there is any.
#
# Methods:
#
# add(p = {progress: 0})
#    Create and return a ProgressBar with the initial properties specified by `p`,
#    which has the following methods available to it:
#
#    p.setProgress(prog)
#        Updates `p`s progress. `prog` is a number between -∞ and 1; if it is
#        negative, a indeterminate progress bar will be displayed.
#
#    p.setLeftText(t), p.setRightText(t), p.setMessage(t)
#        Sets the text displayed to the left of the progress bar, right of the
#        progress bar, or when hovering over it.
#
#    p.destroy()
#        Destroys `p` and removes it from the display stack.

module.exports =
  stack: []

  activate: ->
    return if @activated
    @activated = true
    @emitter = new Emitter

    @overlay = @stackView()
    @view = @tileView()

    @tooltip = new inkTooltip @view, @overlay, => @hasDeterminateBars()

    @tile = @statusBar?.addLeftTile
      item: @view
      priority: -1

  deactivate: ->
    @tooltip.destroy()
    @tile?.destroy()

  consumeStatusBar: (bar) ->
    @statusBar = bar


  create: (p = {progress: 0}) ->
    @activate()
    p.emitter = new Emitter

    p.onDidUpdate = (f) =>
      p.emitter.on 'did-update-progress', f
    p.setProgress = (prog) =>
      oldp = p.progress
      p.progress = prog
      p.emitter.emit 'did-update-progress'
      # if determinate-ness changes, update the stack display
      @emitter.emit 'did-update-stack' unless oldp*prog > 0
    p.setLeftText = (t) =>
      p.leftText = t
      p.emitter.emit 'did-update-progress'
    p.setRightText = (t) =>
      p.rightText = t
      p.emitter.emit 'did-update-progress'
    p.setMessage = (t) =>
      p.msg = t
      p.emitter.emit 'did-update-progress'
    p.destroy = (t) =>
      i = @stack.indexOf p
      return if i < 0
      @stack.splice i, 1
      p.emitter.dispose()
      @emitter.emit 'did-update-stack'
    p.register = =>
      @stack.push p
      @emitter.emit 'did-update-stack'

    p

  # Public API
  add: (prog) ->
    p = create prog
    p.register()
    p

  # update logic
  hasDeterminateBars: ->
    @stack.filter((p) => p.progress >= 0).length is not 0

  onDidUpdateStack: (f) -> @emitter.on 'did-update-stack', f

  onDidUpdateProgress: (f) -> @emitter.on 'did-update-progress', f

  # UI elements:
  progressView: (p) ->
    span = document.createElement 'span'
    prog = document.createElement 'progress'
    prog.classList.add 'ink'
    prog.setAttribute 'max', 1
    span.appendChild prog

    updateView = (prg) =>
      if prg.progress >= 0
        prog.setAttribute 'value', prg.progress
      else
        prog.removeAttribute 'value'

    p.onDidUpdate => updateView p
    updateView p

    span

  msgView: (p, parent) ->
    div = document.createElement 'div'
    div.classList.add 'ink-tooltip-msg'
    div.appendChild.innerText = p.msg

    p.onDidUpdate =>
      if p.msg?.length
        div.innerText = p.msg
        parent.classList.add 'has-tooltip'
      else
        parent.classList.remove 'has-tooltip'

    div

  tableRowView: (p) ->
    tr = document.createElement 'tr'
    # left text
    tdl = document.createElement 'td'
    tdl.classList.add 'progress-tr'
    p.leftText? and tdl.appendChild document.createTextNode p.leftText
    # progress bar
    td = document.createElement 'td'
    td.classList.add 'progress-tr', 'has-tooltip'
    td.appendChild @progressView p
    td.appendChild @msgView p, td
    # right text
    tdr = document.createElement 'td'
    tdr.classList.add 'progress-tr'
    p.rightText? and tdr.appendChild document.createTextNode p.rightText

    p.onDidUpdate =>
      if p.rightText?
        if tdr.firstChild then tdr.removeChild tdr.firstChild
        tdr.appendChild document.createTextNode p.rightText
    # construct the row
    tr.appendChild tdl
    tr.appendChild td
    tr.appendChild tdr

    tr

  stackView: ->
    div = document.createElement 'div'

    table = document.createElement 'table'
    div.appendChild table

    @onDidUpdateStack =>
      # remove all table rows
      while table.firstChild
        table.removeChild table.firstChild
      if not @hasDeterminateBars()
        @tooltip.hide()
      # backwards iteration
      for i in [0...@stack.length].reverse()
        p = @stack[i]
        continue unless p.progress >= 0
        table.appendChild @tableRowView p
        p.emitter.emit 'did-update-progress'

    div

  tileView: ->
    span = document.createElement 'span'
    span.classList.add 'inline-block'
    span.appendChild @tableRowView @create()

    @onDidUpdateStack =>
      span.removeChild span.firstChild
      # find the first determinate progress bar
      global = @stack.find (p) => p.progress >= 0
      # if there is none, use the first one in the stack
      global = @stack[0] unless global?
      # display an empty progress bar if the stack is empty
      global = @create() unless global?
      span.appendChild @progressView global
      global.emitter.emit 'did-update-progress'

    span
