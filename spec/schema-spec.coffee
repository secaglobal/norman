Schema = require("#{LIBS_PATH}/schema");

describe '@Schema', () ->
    describe '#constructor', () ->
        it 'should handle simple structure', () ->
            schema = new Schema 'Car', title: {type: String}, nr:  {type: Number}
            expect(schema.fields.title).be.deep.equal {type: String}
            expect(schema.fields.nr).be.deep.equal {type: Number}

        it 'should handle types', () ->
            schema = new Schema 'Car', title: String, nr: Number
            expect(schema.fields.title).be.deep.equal {type: String}
            expect(schema.fields.nr).be.deep.equal {type: Number}

        it 'should handle collections', () ->
            schema = new Schema 'Car', parts: [Number]
            expect(schema.fields.parts).be.deep.equal {type: Number, collection: true}

        it 'should handle Many-to-Many relations', () ->
            schema = new Schema 'Car', parts: [[String]]
            expect(schema.fields.parts).be.deep.equal {type: String, m2m: true, collection: true}

        it 'should handler _proxy attribute', () ->
            schema = new Schema 'Car', _proxy: 'proxy'
            expect(schema.proxy).be.deep.equal 'proxy'

        it 'should set default field name for relations', () ->
            schema = new Schema 'Car', _proxy: 'proxy'
            expect(schema.defaultFieldName).be.deep.equal 'carId'

