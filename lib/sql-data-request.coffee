DBDataRequest = require './db-data-request'
Collection = require './collection'
SQLQueryBuilder = require './sql-query-builder'
_ = require 'underscore'
Q = require 'q'
Util = require './util'

#@abstract
class SQLDataRequest extends DBDataRequest
    fillTotalCount: () ->
        @_fillTotalCount = true
        @

    find: (model) ->
        builder = @_builder(model.schema.name)
            .setFields(@_fields)
            .setFilters(@_filters or {})
            .setLimit(@_limit)
            .setOffset(@_offset)
            .setOrder(@_order)

        builder.addMeta SQLQueryBuilder.META__TOTAL_COUNT if @_fillTotalCount

        @_proxy.perform(builder)

    save: (models, fillId = true) ->
        deferred = Q.defer()
        onUpdate = []
        onInsert = []
        promises = []

        models.map (model) ->
            model.id or onInsert.push model
            model.hasChanges() and model.id and onUpdate.push model

        @_updateModels(onUpdate, promises) if onUpdate.length
        @_insertModelsAndFillIds(onInsert, promises) if onInsert.length and fillId
        @_insertModels(onInsert, promises) if onInsert.length and not fillId


        Q.allSettled(promises).then (results) ->
            results.forEach (result) ->
                if result.state isnt "fulfilled"
                    deferred.reject result.reason

            deferred.resolve()

        deferred.promise


    delete: (models) ->
        table = models[0].self.schema.name
        ids = _.filter _.pluck(models, 'id'), (v) ->
            v > 0

        @getProxy().perform \
            @_builder(table)
                .setType(SQLQueryBuilder.TYPE__DELETE)
                .setFilters({id: {$in: ids}})
                .compose()

    fillManyToOneRelation: (models, relation) ->
        schema = models.config.model.schema
        config = schema.fields[relation]
        relationSchema = config.type.schema
        fieldName = config.field || Util.lcfirst(relationSchema.name) + 'Id'

        ids = _.uniq _.compact models.pluck fieldName

        return @getProxy().perform(
          @_builder(relationSchema.name).setFilters({id: {$in: ids}}).compose()
        ).then (rows) ->
            models.forEach (m) ->
                return false if not m[fieldName]?
                record = _.findWhere rows, {id: m[fieldName]}
                m[relation] = new config.type record if record

    fillOneToManyRelation: (models, relation) ->
        schema = models.config.model.schema
        config = schema.fields[relation]
        relationSchema = config.type.schema
        fieldName = config.field || Util.lcfirst(schema.name) + 'Id'

        ids = _.compact models.pluck 'id'

        filters = {}
        filters[fieldName] = {$in: ids}

        return @getProxy().perform(
            @_builder(relationSchema.name).setFilters(filters).compose()
        ).then (rows) ->
            models.forEach (m) ->
                return false if not m.id?

                filters = {}
                filters[fieldName] = m.id
                options = {model: config.type}
                col = new Collection([], options)
                m[relation] = col
                col.reset(_.where(rows, filters))

    fillManyToManyRelation: (models, relation) ->
        self = @
        schema = models.config.model.schema
        relationModel = schema.fields[relation].type
        relationSchema = relationModel.schema
        mainTable = schema.name
        relationTable = relationSchema.name
        mainCrossField = schema.defaultFieldName
        relationCrossField = relationSchema.defaultFieldName
        crosstable = [mainTable, relationTable].sort().join('__')

        ids = _.compact models.pluck('id')
        filters = {}
        filters[mainCrossField] = {$in: ids}

        crossvalues = []

        @getProxy().perform(
          @_builder(crosstable).setFilters(filters).compose()
        ).then (rows) ->
            ids = _.uniq _.compact _.pluck rows, relationCrossField
            crossvalues = _.groupBy(rows, (v) -> v[mainCrossField])

            self.getProxy().perform(
              self._builder(relationTable).setFilters({id: {$in: ids}}).compose()
            )
        .then (rows) ->
            models.forEach (m) ->
                return false if not m.id?

                mainId = m.id
                options = {model: relationModel}
                col = new Collection([], options)
                m[relation] = col

                if not crossvalues[mainId]?
                    return

                relationIds = _.pluck(crossvalues[mainId], relationCrossField)
                related = _.filter rows, (v) -> _.contains(relationIds, v.id)
                col.reset related

    fillVirtualOneToOneRelation: (models, relation) ->
        throw 'SQL collections dows not support virtual relations'

    fillVirtualOneToManyRelation: (models, relation) ->
        throw 'SQL collections dows not support virtual relations'

    saveManyToManyRelations: (parent, children, relation) ->
        parentId = parent.id
        parentSchema = parent.self.schema
        childModel = parentSchema.fields[relation].type
        childSchema = childModel.schema
        crossTable = [parentSchema.name, childSchema.name].sort().join('__')
        parentCrossField = parentSchema.defaultFieldName
        childCrossField = childSchema.defaultFieldName
        proxy = @getProxy()
        builder = @_builder

        ids = _.compact children.pluck('id')
        filters = {}
        filters[parentCrossField] = parent.id
        filters[childCrossField] = {$nin: ids} if ids.length

        query = builder(crossTable, SQLQueryBuilder.TYPE__DELETE).setFilters(filters)
        proxy.perform(query).then () ->
            if ids.length
                query = builder(crossTable, SQLQueryBuilder.TYPE__INSERT)
                    .setFields([parentCrossField, childCrossField])
                    .insertValues(ids.map (id) -> [parentId, id])

                proxy.perform query

    _insertModels: (models, promises) ->
        table = models[0].schema.name

        groups = _.groupBy models, (model) ->
            return _.intersection(_.keys(model), model.schema.keys).sort().join(';')

        for key, group of groups
            fields = key.split(';')
            values = []
            for model in group
                value = []
                values.push value
                for field in fields
                    value.push model[field]

            promises.push \
                @getProxy().perform \
                    @_builder(table)
                        .insertValues(values)
                        .setFields(fields)
                        .compose()

    _insertModelsAndFillIds: (models, promises) ->
        table = models[0].schema.name

        for model in models
            fields = _.intersection(_.keys(model), model.schema.keys)
            values = []

            for field in fields
                values.push model[field]

            promises.push \
                @getProxy().perform(
                    @_builder(table)
                        .insertValues([values])
                        .setFields(fields)
                        .compose()

                ).then @_wrapInsertCallback(model)

    _wrapInsertCallback: (model) ->
        (result) ->
            model.id = result.insertId

    _updateModels: (models, promises) ->
        table = models[0].schema.name
        for model in models
            promises.push \
                @getProxy().perform \
                    @_builder(table)
                    .updateFields(model.getChangedAttributes())
                    .setFilters({id: model.id})
                    .compose()

    _builder: (table) ->
        throw 'not implemented'

module.exports = SQLDataRequest;