using BinaryProvider # requires BinaryProvider 0.3.0 or later
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, String["libRmath"], :libRmath),
]
bin_prefix = "https://github.com/staticfloat/RmathBuilder/releases/download/v0.2.0-1"
download_info = Dict(
    Linux(:aarch64, :glibc) => ("$bin_prefix/libRmath.aarch64-linux-gnu.tar.gz", "53f070e19f2dc23c92a2e7ecaa4eb2d2d66d97e31cf9065f8ad93fb7f608254e"),
    Linux(:aarch64, :musl) => ("$bin_prefix/libRmath.aarch64-linux-musl.tar.gz", "b5202bc8c8cd019b3139ab6c95a9e60a184752c641ef75bd705ea22fa1f496f2"),
    Linux(:armv7l, :glibc, :eabihf) => ("$bin_prefix/libRmath.arm-linux-gnueabihf.tar.gz", "535d74c9664a1575d1e6c72f6384c6c5e330269a139f33cb57e8cb8b3fdf9e8d"),
    Linux(:armv7l, :musl, :eabihf) => ("$bin_prefix/libRmath.arm-linux-musleabihf.tar.gz", "d1e8f042c3a1e108d4241e25979182bb75c58eff46367da795394098fb7fa6ea"),
    Linux(:i686, :glibc) => ("$bin_prefix/libRmath.i686-linux-gnu.tar.gz", "8ac9512567749d44bd5804913c049f09b36a65afee29d1433b170864d803d940"),
    Linux(:i686, :musl) => ("$bin_prefix/libRmath.i686-linux-musl.tar.gz", "c07ce055a0016184142c215880b79de58ec73ab613a6a1f5a96b9cd89994b7ea"),
    Windows(:i686) => ("$bin_prefix/libRmath.i686-w64-mingw32.tar.gz", "713ad202e6aa97b60f4ae0d0c1aa51a463a831ddb84a8bc0284dbc5c206c82be"),
    Linux(:powerpc64le, :glibc) => ("$bin_prefix/libRmath.powerpc64le-linux-gnu.tar.gz", "cfff5005be3c7c8fff68aa79d2b4730f77a5478d72d1237a6d99e5c8b54e12f4"),
    MacOS(:x86_64) => ("$bin_prefix/libRmath.x86_64-apple-darwin14.tar.gz", "75b5ed2208676eb05576622baac2c4d70c3bb0588ad3d562938eeed9fee7aaa4"),
    Linux(:x86_64, :glibc) => ("$bin_prefix/libRmath.x86_64-linux-gnu.tar.gz", "e690b50e77a1a501a7f5c25a19b345dddc5447dcfeeaee9f3ae36dfc3d8540f4"),
    Linux(:x86_64, :musl) => ("$bin_prefix/libRmath.x86_64-linux-musl.tar.gz", "e70f991ac8c5eccd5f5f38e79200c8203e43393c2ef525f717578f03c1353fe7"),
    FreeBSD(:x86_64) => ("$bin_prefix/libRmath.x86_64-unknown-freebsd11.1.tar.gz", "36ceb06979183c8d89fd32e551d5aae8f879300a8ecb89ab209e17765c9c1c75"),
    Windows(:x86_64) => ("$bin_prefix/libRmath.x86_64-w64-mingw32.tar.gz", "12929d34ec0fd3e29c0633410c08396b21989513fcd4d28ed845c3cabf316a19"),
)
unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)
if haskey(download_info, platform_key())
    url, tarball_hash = download_info[platform_key()]
    if unsatisfied || !isinstalled(url, tarball_hash; prefix=prefix)
        install(url, tarball_hash; prefix=prefix, force=true, verbose=verbose)
    end
elseif unsatisfied
    error("Your platform $(triplet(platform_key())) is not supported by this package!")
end
write_deps_file(joinpath(@__DIR__, "deps.jl"), products)