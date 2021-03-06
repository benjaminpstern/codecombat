ThangState = require './thang_state'
{thangNames} = require './names'
{ArgumentError} = require './errors'
Rand = requre './rand'

module.exports = class Thang
  @className: "Thang"
  @random = new Rand 0
  #Random ordering for each sprite name
  @ordering: (spriteName) ->
    Thang.orders ?= {}
    names = thangNames[spriteName]
    if names
      len = names.length
      array = Thang.orders[spriteName]
      if !array?
        array = @random.randArray len
        Thang.orders[spriteName] = array
    else
      array = []
    array
  @nextID: (spriteName) ->
    Thang.lastIDNums ?= {}
    names = thangNames[spriteName]
    order = @ordering spriteName
    if names
      lastIDNum = Thang.lastIDNums[spriteName]
      idNum = (if lastIDNum? then lastIDNum + 1 else 0)
      Thang.lastIDNums[spriteName] = idNum
      id = names[order[idNum % names.length]]
      if idNum >= names.length
        id += Math.floor(idNum / names.length) + 1
    else
      Thang.lastIDNums[spriteName] = if Thang.lastIDNums[spriteName]? then Thang.lastIDNums[spriteName] + 1 else 0
      id = spriteName + (Thang.lastIDNums[spriteName] or '')
    id
  @resetThangIDs: -> Thang.lastIDNums = {}

  constructor: (@world, @spriteName, @id) ->
    @spriteName ?= @constructor.className
    @id ?= @constructor.nextID @spriteName
    @addTrackedProperties ['exists', 'boolean']  # TODO: move into Systems/Components, too?
    #console.log "Generated #{@toString()}."

  updateRegistration: ->
    system.register @ for system in @world.systems

  publishNote: (channel, event) ->
    event.thang = @
    @world.publishNote channel, event

  addComponents: (components...) ->
    # We don't need to keep the components around after attaching them, but we will keep their initial config for recreating Thangs
    @components ?= []
    for [componentClass, componentConfig] in components
      @components.push [componentClass, componentConfig]
      if _.isString componentClass  # We had already turned it into a string, so re-classify it momentarily
        componentClass = @world.classMap[componentClass]
      else
        @world?.classMap[componentClass.className] ?= componentClass
      c = new componentClass componentConfig
      c.attach @

  # [prop, type]s of properties which have values tracked across WorldFrames. Also call keepTrackedProperty some non-expensive time when you change it or it will be skipped.
  addTrackedProperties: (props...) ->
    @trackedPropertiesKeys ?= []
    @trackedPropertiesTypes ?= []
    @trackedPropertiesUsed ?= []
    for [prop, type] in props
      unless type in ThangState.trackedPropertyTypes
        # How should errors for busted Components work? We can't recover from this and run the world.
        throw new Error "Type #{type} for property #{prop} is not a trackable property type: #{trackedPropertyTypes}"
      oldPropIndex = @trackedPropertiesKeys.indexOf prop
      if oldPropIndex is -1
        @trackedPropertiesKeys.push prop
        @trackedPropertiesTypes.push type
        @trackedPropertiesUsed.push false
      else
        oldType = @trackedPropertiesTypes[oldPropIndex]
        if type isnt oldType
          throw new Error "Two types were specified for trackable property #{prop}: #{oldType} and #{type}."

  keepTrackedProperty: (prop) ->
    # Hmm; can we do this faster?
    propIndex = @trackedPropertiesKeys.indexOf prop
    if propIndex isnt -1
      @trackedPropertiesUsed[propIndex] = true

  # @trackedFinalProperties: names of properties which need to be tracked once at the end of the World; don't worry about types
  addTrackedFinalProperties: (props...) ->
    @trackedFinalProperties ?= []
    @trackedFinalProperties = @trackedFinalProperties.concat (k for k in props when not (k in @trackedFinalProperties))

  getState: ->
    @_state = new ThangState @
  setState: (state) ->
    @_state = state.restore()

  toString: -> @id

  createMethodChain: (methodName) ->
    @methodChains ?= {}
    chain = @methodChains[methodName]
    return chain if chain
    chain = @methodChains[methodName] = {original: @[methodName], user: null, components: []}
    @[methodName] = _.partial @callChainedMethod, methodName  # Optimize! _.partial is fastest I've found
    chain

  appendMethod: (methodName, newMethod) ->
    # Components add methods that come after the original method
    @createMethodChain(methodName).components.push newMethod

  callChainedMethod: (methodName, args...) ->
    # Optimize this like crazy--but how?
    chain = @methodChains[methodName]
    primaryMethod = chain.user or chain.original
    ret = primaryMethod?.apply @, args
    for componentMethod in chain.components
      ret2 = componentMethod.apply @, args
      ret = ret2 ? ret  # override return value only if not null
    ret

  getMethodSource: (methodName) ->
    source = {}
    if @methodChains? and methodName of @methodChains
      chain = @methodChains[methodName]
      source.original = chain.original.toString()
      source.user = chain.user?.toString()
    else
      source.original = @[methodName]?.toString() ? ""
    source.original = Aether.getFunctionBody source.original
    source

  serialize: ->
    o = {spriteName: @spriteName, id: @id, components: [], finalState: {}}
    for [componentClass, componentConfig], i in (@components ? [])
      if _.isString componentClass
        componentClassName = componentClass
      else
        componentClassName = componentClass.className
        @world.classMap[componentClass.className] ?= componentClass
      o.components.push [componentClassName, componentConfig]
    for trackedFinalProperty in @trackedFinalProperties ? []
      # TODO: take some (but not all) of serialize logic from ThangState to handle other types
      o.finalState[trackedFinalProperty] = @[trackedFinalProperty]
    o

  @deserialize: (o, world, classMap) ->
    t = new Thang world, o.spriteName, o.id
    for [componentClassName, componentConfig] in o.components
      componentClass = classMap[componentClassName]
      t.addComponents [componentClass, componentConfig]
    for prop, val of o.finalState
      # TODO: take some (but not all) of deserialize logic from ThangState to handle other types
      t[prop] = val
    t
