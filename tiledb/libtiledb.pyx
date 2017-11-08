from cpython.version cimport PY_MAJOR_VERSION
from libc.stdio cimport stdout

from os.path import abspath

def version():
    cdef:
        int major = 0
        int minor = 0
        int rev = 0
    tiledb_version(&major, &minor, &rev)
    return major, minor, rev

cdef unicode ustring(s):
    if type(s) is unicode:
        return <unicode>s
    elif PY_MAJOR_VERSION < 3 and isinstance(s, bytes):
        return (<bytes> s).decode('ascii')
    elif isinstance(s, unicode):
        return unicode(s)
    raise TypeError(
        "ustring() must be a string or a bytes-like object"
        ", not {0!r}".format(type(s)))


class TileDBError(Exception):
    pass


cdef check_error(Ctx ctx, int rc):
    ctx_ptr = ctx.ptr
    if rc == TILEDB_OK:
        return
    if rc == TILEDB_OOM:
        raise MemoryError()
    cdef int ret = TILEDB_OK
    cdef tiledb_error_t* err = NULL
    ret = tiledb_error_last(ctx_ptr, &err)
    if ret != TILEDB_OK:
        tiledb_error_free(ctx_ptr, err)
        if ret == TILEDB_OOM:
            raise MemoryError()
        raise TileDBError("error retrieving error object from ctx")
    cdef const char* err_msg = NULL
    ret = tiledb_error_message(ctx_ptr, err, &err_msg)
    if ret != TILEDB_OK:
        tiledb_error_free(ctx_ptr, err)
        if ret == TILEDB_OOM:
            return MemoryError()
        raise TileDBError("error retrieving error message from ctx")
    message_string = err_msg.decode('UTF-8', 'strict')
    tiledb_error_free(ctx_ptr, err)
    raise TileDBError(message_string)


cdef class Ctx(object):

    cdef tiledb_ctx_t* ptr

    def __cinit__(self):
        cdef int rc = tiledb_ctx_create(&self.ptr)
        if rc == TILEDB_OOM:
            raise MemoryError()
        if rc == TILEDB_ERR:
            raise TileDBError("unknown error creating tiledb.Ctx")

    def __dealloc__(self):
        if self.ptr is not NULL:
            tiledb_ctx_free(self.ptr)


cdef tiledb_datatype_t _tiledb_dtype(dtype) except TILEDB_CHAR:
    if dtype == "i4":
        return TILEDB_INT32
    elif dtype == "u4":
        return TILEDB_UINT32
    elif dtype == "i8":
        return TILEDB_INT64
    elif dtype == "u8":
        return TILEDB_UINT64
    elif dtype == "f4":
        return TILEDB_FLOAT32
    elif dtype == "f8":
        return TILEDB_FLOAT64
    elif dtype == "i1":
        return TILEDB_INT8
    elif dtype == "u1":
        return TILEDB_UINT8
    elif dtype == "i2":
        return TILEDB_INT16
    elif dtype == "u2":
        return TILEDB_UINT16
    raise TypeError("data type {0!r} not understood".format(dtype))

cdef tiledb_compressor_t _tiledb_compressor(c) except TILEDB_NO_COMPRESSION:
    if c is None:
        return TILEDB_NO_COMPRESSION
    elif c == "gzip":
        return TILEDB_GZIP
    elif c == "zstd":
        return TILEDB_ZSTD
    elif c == "lz4":
        return TILEDB_LZ4
    elif c == "blosc-lz":
        return TILEDB_BLOSC
    elif c == "blosc-lz4":
        return TILEDB_BLOSC_LZ4
    elif c == "blosc-lz4hc":
        return TILEDB_BLOSC_LZ4HC
    elif c == "blosc-snappy":
        return TILEDB_BLOSC_SNAPPY
    elif c == "blosc-zstd":
        return TILEDB_BLOSC_ZSTD
    elif c == "rle":
        return TILEDB_RLE
    elif c == "bzip2":
        return TILEDB_BZIP2
    elif c == "double-delta":
        return TILEDB_DOUBLE_DELTA
    raise AttributeError("unknown compressor: {0!r}".format(c))

cdef unicode _tiledb_compressor_string(tiledb_compressor_t c):
    if c == TILEDB_NO_COMPRESSION:
        return u"none"
    elif c == TILEDB_GZIP:
        return u"gzip"
    elif c == TILEDB_ZSTD:
        return u"zstd"
    elif c == TILEDB_LZ4:
        return u"lz4"
    elif c == TILEDB_BLOSC:
        return u"blosc-lz"
    elif c == TILEDB_BLOSC_LZ4:
        return u"blosc-lz4"
    elif c == TILEDB_BLOSC_LZ4HC:
       return u"blosc-lz4hc"
    elif c == TILEDB_BLOSC_SNAPPY:
        return u"blosc-snappy"
    elif c == TILEDB_BLOSC_ZSTD:
        return u"blosc-zstd"
    elif c == TILEDB_RLE:
        return u"rle"
    elif c == TILEDB_BZIP2:
        return u"bzip2"
    elif c == TILEDB_DOUBLE_DELTA:
        return u"double-delta"

cdef class Attr(object):

    cdef Ctx ctx
    cdef tiledb_attribute_t* ptr

    def __cinit__(self):
        self.ptr = NULL

    def __dealloc__(self):
        if self.ptr is not NULL:
            tiledb_attribute_free(self.ctx.ptr, self.ptr)

    # TODO: use numpy compund dtypes to choose number of cells
    def __init__(self, Ctx ctx,  name=None, dtype='f8', compressor=None, level=-1):
        uname = ustring(name).encode('UTF-8')
        cdef tiledb_attribute_t* attr_ptr = NULL
        cdef tiledb_compressor_t compr = TILEDB_NO_COMPRESSION
        cdef tiledb_datatype_t tiledb_dtype = _tiledb_dtype(dtype)
        check_error(ctx,
            tiledb_attribute_create(ctx.ptr, &attr_ptr, uname, tiledb_dtype))
        if compressor is not None:
            compr = _tiledb_compressor(compressor)
            check_error(ctx,
                tiledb_attribute_set_compressor(ctx.ptr, attr_ptr, compr, level))
        self.ctx = ctx
        self.ptr = attr_ptr


    def dump(self):
        check_error(self.ctx,
            tiledb_attribute_dump(self.ctx.ptr, self.ptr, stdout))

    @property
    def name(self):
        cdef const char* c_name = NULL
        check_error(self.ctx,
            tiledb_attribute_get_name(self.ctx.ptr, self.ptr, &c_name))
        return c_name.decode('UTF-8')

    @property
    def compressor(self):
        cdef int c_level = -1
        cdef tiledb_compressor_t compr = TILEDB_NO_COMPRESSION
        check_error(self.ctx,
            tiledb_attribute_get_compressor(self.ctx.ptr, self.ptr, &compr, &c_level))
        return (_tiledb_compressor_string(compr), int(c_level))

cdef class Domain(object):

    cdef Ctx ctx
    cdef tiledb_domain_t* ptr

    def __cinit__(self):
        self.ptr = NULL

    def __dealloc__(self):
        if self.ptr is not NULL:
            tiledb_domain_free(self.ctx.ptr, self.ptr)

    def __init__(self, Ctx ctx, *dims, dtype='i8'):
        for d in dims:
            if not isinstance(d, Dim):
                raise TypeError("unknown dimension type {0!r}".format(d))
        cdef tiledb_datatype_t domain_type = _tiledb_dtype(dtype)
        cdef tiledb_domain_t* domain_ptr = NULL
        check_error(ctx,
                    tiledb_domain_create(ctx.ptr, &domain_ptr, domain_type))
        cdef int rc
        cdef uint64_t tile_extent
        cdef uint64_t[2] dim_range
        for d in dims:
            ulabel = ustring(d.label).encode('UTF-8')
            dim_range[0] = d.dim[0]
            dim_range[1] = d.dim[1]
            tile_extent = d.tile
            rc = tiledb_domain_add_dimension(
                ctx.ptr, domain_ptr, ulabel, &dim_range, &tile_extent)
            if rc != TILEDB_OK:
                tiledb_domain_free(ctx.ptr, domain_ptr)
                check_error(ctx, rc)
        self.ctx = ctx
        self.ptr = domain_ptr

    def dump(self):
        check_error(self.ctx,
                    tiledb_domain_dump(self.ctx.ptr, self.ptr, stdout))


cdef class Dim(object):

    cdef unicode label
    cdef tuple dim
    cdef object tile

    def __init__(self, label=None, dim=None, tile=None):
        self.label = label
        self.dim = (dim[0], dim[1])
        self.tile = tile

    @property
    def label(self):
        return self.label

    @property
    def dim(self):
        return self.dim

    @property
    def tile(self):
        return self.tile


cdef tiledb_layout_t _tiledb_layout(order) except TILEDB_UNORDERED:
    if order == "row-major":
        return TILEDB_ROW_MAJOR
    elif order == "col-major":
        return TILEDB_COL_MAJOR
    elif order == "global":
        return TILEDB_GLOBAL_ORDER
    elif order == None or order == "unordered":
        return TILEDB_UNORDERED
    raise AttributeError("unknown tiledb layout: {0!r}".format(order))


cdef class Array(object):

    cdef Ctx ctx
    cdef unicode name
    cdef tiledb_array_metadata_t* ptr

    def __cinit__(self):
        self.ptr = NULL

    def __dealloc__(self):
        if self.ptr is not NULL:
            tiledb_array_metadata_free(self.ctx.ptr, self.ptr)

    def __init__(self, Ctx ctx,
                 unicode name,
                 domain=None,
                 attrs=[],
                 cell_order='row-major',
                 tile_order='row-major',
                 capacity=0,
                 sparse=False):
        uname = ustring(name).encode('UTF-8')
        cdef tiledb_array_metadata_t* metadata_ptr = NULL
        check_error(ctx,
            tiledb_array_metadata_create(ctx.ptr, &metadata_ptr, uname))
        cdef tiledb_layout_t cell_layout = _tiledb_layout(cell_order)
        cdef tiledb_layout_t tile_layout = _tiledb_layout(tile_order)
        cdef tiledb_array_type_t array_type = TILEDB_SPARSE if sparse else TILEDB_DENSE
        tiledb_array_metadata_set_array_type(
            ctx.ptr, metadata_ptr, array_type)
        tiledb_array_metadata_set_cell_order(
            ctx.ptr, metadata_ptr, cell_layout)
        tiledb_array_metadata_set_tile_order(
            ctx.ptr, metadata_ptr, tile_layout)
        cdef uint64_t c_capacity = 0
        if capacity > 0:
            c_capacity = <uint64_t>capacity
            tiledb_array_metadata_set_capacity(ctx.ptr, metadata_ptr, c_capacity)
        cdef tiledb_domain_t* domain_ptr = (<Domain>domain).ptr
        tiledb_array_metadata_set_domain(
            ctx.ptr, metadata_ptr, domain_ptr)
        cdef tiledb_attribute_t* attr_ptr = NULL
        for attr in attrs:
            attr_ptr = (<Attr>attr).ptr
            tiledb_array_metadata_add_attribute(
                ctx.ptr, metadata_ptr, attr_ptr)
        cdef int rc = TILEDB_OK
        rc = tiledb_array_metadata_check(ctx.ptr, metadata_ptr)
        if rc != TILEDB_OK:
            tiledb_array_metadata_free(ctx.ptr, metadata_ptr)
            check_error(ctx, rc)
        rc = tiledb_array_create(ctx.ptr, metadata_ptr)
        if rc != TILEDB_OK:
            check_error(ctx, rc)
        self.name = uname
        self.ptr = metadata_ptr


cdef unicode unicode_path(path):
    return ustring(abspath(path)).encode('UTF-8')

def group_create(Ctx ctx, path):
    upath = unicode_path(path)
    cdef const char* c_path = upath
    check_error(ctx,
       tiledb_group_create(ctx.ptr, c_path))
    return upath.decode('UTF-8')

def object_type(Ctx ctx, path):
    upath = unicode_path(path)
    cdef const char* c_path = upath
    cdef tiledb_object_t obj = TILEDB_INVALID
    check_error(ctx,
       tiledb_object_type(ctx.ptr, c_path, &obj))
    return obj

def delete(Ctx ctx, path):
    upath = unicode_path(path)
    cdef const char* c_path = upath
    check_error(ctx,
       tiledb_delete(ctx.ptr, c_path))
    return

def move(Ctx ctx, oldpath, newpath, force=False):
    uoldpath = unicode_path(oldpath)
    unewpath = unicode_path(newpath)
    cdef const char* c_oldpath = uoldpath
    cdef const char* c_newpath = unewpath
    cdef int c_force = 0
    if force:
       c_force = True
    check_error(ctx,
        tiledb_move(ctx.ptr, c_oldpath, c_newpath, c_force))
    return

cdef int walk_callback(const char* c_path,
                       tiledb_object_t obj,
                       void* pyfunc):
    objtype = None
    if obj == TILEDB_ARRAY:
        objtype = "array"
    elif obj == TILEDB_GROUP:
        objtype = "group"
    try:
        (<object> pyfunc)(c_path.decode('UTF-8'), objtype)
    except StopIteration:
        return 0
    return 1

def walk(Ctx ctx, path, func, order="preorder"):
    upath = unicode_path(path)
    cdef const char* c_path = upath
    cdef tiledb_walk_order_t c_order
    if order == "postorder":
        c_order = TILEDB_POSTORDER
    elif order == "preorder":
        c_order = TILEDB_PREORDER
    else:
        raise AttributeError("unknown walk order {}".format(order))
    check_error(ctx,
        tiledb_walk(ctx.ptr, c_path, c_order, walk_callback, <void*> func))
    return
