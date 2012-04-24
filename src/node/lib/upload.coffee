stream = require('stream')
events = require('events')

multipart = require('./multipart')


class exports.UploadRequest extends events.EventEmitter
    constructor: (@request) ->
    begin: () ->
        if @request.headers['content-type'].indexOf('application/octet-stream') != -1
            @headers = @request.headers

            stream = new stream.Stream
            stream.headers = @request.headers
            stream.filename = @request.headers['x-file-name']
            @emit('file', stream)
        
            @request.on 'data', (chunk) -> stream.emit('data', chunk)
            @request.on 'end', =>
                stream.readable = false
                stream.emit('end')

            @request.on 'error', (error) =>
                stream.readable = false
                stream.emit('error', error)
        
        else if @request.headers['content-type'].indexOf('multipart/') != -1
            boundary = @request.headers['content-type'].match(/boundary=([^]+)/i)[1]
            parser = new multipart.MultipartParser(boundary)

            headerField = null
            headerValue = null
            stream = null

            parser.on 'partBegin', () =>
                stream = new stream.Stream
                stream.headers = {}
                stream.filename = null
                headerField = ''
                headerValue = ''

            parser.on 'headerField', (b, start, end) =>
                headerField += b.toString('utf-8', start, end)

            parser.on 'headerValue', (b, start, end) =>
                headerValue += b.toString('utf-8', start, end)

            parser.on 'headerEnd', () =>
                stream.headers[headerField.toLowerCase()] = headerValue
                headerField = ''
                headerValue = ''

            parser.on 'headersEnd', () =>
                if stream.headers['content-disposition']
                    contentDisposition = stream.headers['content-disposition']
                    if m = contentDisposition.match(/filename="([^]+)"/i)
                        stream.headers['content-type'] = 'application/octet-stream'
                        stream.filename = m[1].substr(m[1].lastIndexOf('\\') + 1)
                        stream.readable = true
                        @emit('file', stream)

            parser.on 'partData', (b, start, end) =>
                if stream and stream.filename
                    stream.emit('data', b.slice(start, end))

            parser.on 'partEnd', () =>
                if stream and stream.filename
                    stream.readable = false
                    stream.emit('end')

            @request.on 'data', (chunk) => parser.write(chunk)
            @request.on 'end', () => parser.end()
            @request.on 'error', (error) =>
                if stream and stream.filename
                    stream.readable = false
                    stream.emit('error', error)
        

