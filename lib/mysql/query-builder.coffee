Utils = require '../util'
_ = require 'underscore'
SQLQueryBuilder = require '../sql-query-builder'

class MysqlQueryBuilder extends SQLQueryBuilder
    constructor: (@_type = MysqlQueryBuilder.TYPE__SELECT) ->
        @_meta = []
        @_fields = []
        @

    setType: (@_type) ->
        @

    setTable: (@_table) ->
        @

    setFilters: (@_filters) ->
        @

    setFields: (fields) ->
        @_fields = if _.isArray(fields) then fields else _.toArray(arguments)
        @

    setLimit: (@_limit) ->
        @

    setOffset: (@_offset) ->
        @

    setOrder: (@_order) ->
        @

    updateFields: (@_newValues) ->
        @_type = MysqlQueryBuilder.TYPE__UPDATE
        @

    insertValues: (@_insertValues) ->
        @_type = MysqlQueryBuilder.TYPE__INSERT
        @

    addMeta: (flag) ->
        @_meta.push.apply @_meta, arguments
        @

    hasMeta: (flag) ->
        _.contains @_meta, flag

    compose: () ->
        @["_compose#{@_type}"]()

    _composeSelect: () ->
        parts = [
            @_composeWhereClouse(),
            @_composeOrderClouse(),
            @_composeLimitClouse(),
            @_composeOffsetClouse()
        ].join('')

        meta = ''
        meta = @_meta.join(' ') + ' ' if @_meta.length
        fields = @_composeFieldsClouse()
        fields = '*' if not fields

        "select #{meta}#{fields} from `#{@_table}`#{parts}"

    _composeUpdate: () ->
        valuesRep = ("`#{n}`=#{MysqlQueryBuilder._escape(v)}" for n, v of @_newValues).join(',')

        "update `#{@_table}` set #{valuesRep}#{@_composeWhereClouse()}#{@_composeLimitClouse()}"

    _composeDelete: () ->
        "delete from `#{@_table}`#{@_composeWhereClouse()}#{@_composeLimitClouse()}"

    _composeInsert: () ->
        fields = @_composeFieldsClouse()
        values = (MysqlQueryBuilder._escape(set) for set in @_insertValues).join(',')
        "insert into `#{@_table}`(#{fields}) values#{values}"

    _composeFieldsClouse: () ->
        (MysqlQueryBuilder._escapeField(field)for field in @_fields).join(',')

    _composeWhereClouse: () ->
        whereClouse = ''
        whereClouse = (MysqlQueryBuilder._convertFilters @_filters) if @_filters
        whereClouse = " where #{whereClouse}" if whereClouse.length

    _composeLimitClouse: () ->
        if @_limit then " limit #{parseInt(@_limit)}" else ''

    _composeOffsetClouse: () ->
        if @_offset and @_limit then " offset #{parseInt(@_offset)}" else ''

    _composeOrderClouse: () ->
        res = ''

        if @_order
            parts = []
            for field, order of @_order when order
                cl = MysqlQueryBuilder._escapeField(field)
                cl += ' desc' if order < 0
                parts.push cl

            res = ' order by ' + parts.join(',') if parts.length
        return res

    @_convertFilters: (filters, glue = 'and') ->
        parts = []

        for filter, value of filters
            if @_logicalOperators[filter]
                subexpressions = []
                for expression in value
                    subexpressions.push '(' + @_convertFilters(expression) + ')'
                parts.push '(' + subexpressions.join(" #{@_logicalOperators[filter]} ") + ')';
            else
                parts.push @_convertFilter(filter, value)

        parts.join " #{glue} "

    @_convertFilter: (filter, value) ->
        isOperator = !!@_comparisonOperators[filter]

        # RETURN WITHOUT FILTER
        operator = if isOperator then @_comparisonOperators[filter] else '='

        if Utils.isHashMap(value)
            return "#{@_escapeField(filter)}#{@_convertFilters(value)}"

        filter = '' if isOperator
        operator = ' is ' if value is null

        return @_escapeField(filter) + operator + @_escape(value)

    @_escape: (value) ->
        #TODO prepare real escape
        _this = @
        if Utils.isArray(value)
            return '(' + value.map (v) ->
                _this._escape v
            .join(',') + ')'
        else if value?
            return "'#{value.toString().replace(/\\/g, '\\\\').replace(/['"]/g, '\\\'')}'"
        else
            return 'null'

    @_escapeField: (field) ->
        field = field.replace /[^\w\.]/g, ''
        if not field.length or /\./.test field then field else "`#{field}`"

module.exports = MysqlQueryBuilder;