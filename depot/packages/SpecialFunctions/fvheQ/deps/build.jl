using BinaryProvider # requires BinaryProvider 0.4.0 or later
const forcecompile = get(ENV, "JULIA_SPECIALFUNCTIONS_BUILD_SOURCE", "false") == "true"
const verbose = "--verbose" in ARGS
const prefix = Prefix(get(filter(!isequal("verbose"), ARGS), 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, String["libopenspecfun"], :openspecfun),
]
bin_prefix = "https://github.com/JuliaMath/OpenspecfunBuilder/releases/download/v0.5.3-3"
download_info = Dict(
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-gnu-gcc4.tar.gz",
         "7afa17d39b0e764cb2485b4487819bd6cc2d0ade1d66eccf244a61f06022ee20"),
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-gnu-gcc7.tar.gz",
         "2502c8ff21078d78de3d2da039f0ff27510513e88389287dedc8a0dae0226732"),
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-gnu-gcc8.tar.gz",
         "fd1a373bd618ce07aa76984c1532c1e1262c138907fd9bc2d988e4b97ee87459"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-musl-gcc4.tar.gz",
         "f2e09335ce251148bad2442af8ca3f4da554adb0020731ba81b760c0f4ca9bf0"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-musl-gcc7.tar.gz",
         "c407910c4cf3bafa54302f804e31b57bd1c4a6179e416cd04b45389243481a98"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.aarch64-linux-musl-gcc8.tar.gz",
         "67b7450516bc0638bf34634f7036fb4d1f6e27f40f30e9d1d1096896a3928817"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-gnueabihf-gcc4.tar.gz",
         "56c9d3fe31d14806060f2c65a2e52b0b4c74b08b801060e5f7897e738fdff624"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-gnueabihf-gcc7.tar.gz",
         "877032790dc274df0a12c8c7507991b76b46525173f8ef19b703c3ca598cd2dc"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-gnueabihf-gcc8.tar.gz",
         "3af0a5535645bfe1132c7226f2c9b26277d272df0fa1d22515755a3d6180078d"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-musleabihf-gcc4.tar.gz",
         "1dd62ca5d5971b068074cb6dd1fd35965cba17ae01d221f5c6ab71a478a7fa4b"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-musleabihf-gcc7.tar.gz",
         "586b280f6cc22fb05cba9054a5d8fecff353e6eb1cf1a55c83fdcd5b24ef2683"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.arm-linux-musleabihf-gcc8.tar.gz",
         "1938a8cd65dfe3c1a6a118f6eb751ffa70be7af817fd29831f0ffbfdbce703ab"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-gnu-gcc4.tar.gz",
         "9e15a95e03428a5155ab8540d4b1c02c4da9bc1f66e9cf0f6829d752be35d233"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-gnu-gcc7.tar.gz",
         "6f606b30921671e6b2747274f2ee1c42c67309116e1be4f2efa4d95f2c2480d6"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-gnu-gcc8.tar.gz",
         "1112ab4f6114eed32aea6079bfd69140b5a057b6c94bd8e0a033d283906f5d6b"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-musl-gcc4.tar.gz",
         "4f2c6c225f3f299918bfe96c09d3ea6699e447cf4b0615a45614b6df7b8700da"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-musl-gcc7.tar.gz",
         "d4ba0747da4a8884a96a0ddab5a7b8387724a7395caa46e4b4d4de63cd894756"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-linux-musl-gcc8.tar.gz",
         "adff04533751ba348905f490f774c4cc998d0c96704e0c0883ba73b2c6f0d6b0"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-w64-mingw32-gcc4.tar.gz",
         "9f6816bdf1a326ba7af7b51befc2a39a159b6be439ea9e0f7e6908e44b249f4f"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-w64-mingw32-gcc7.tar.gz",
         "2d2c10f0620ffd4575b2b0f3c99dc451f189f9b41d9ff7c1770ba0836433c86b"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.i686-w64-mingw32-gcc8.tar.gz",
         "abbef77bf9404c65a3505e0f86c62b45711d7421b183636e81803f8cfb27a321"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.powerpc64le-linux-gnu-gcc4.tar.gz",
         "786ba99b3fec5a1d03f0c3f4df670105439994a2fc105a3bfe5214bb923adcb1"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.powerpc64le-linux-gnu-gcc7.tar.gz",
         "78334155f048bc13d65a6d8a8c60cd03dfae3cb23ae29c957b2db2f903e93bcb"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.powerpc64le-linux-gnu-gcc8.tar.gz",
         "8fc88fe37ce3111a21c2c4b4e942f1d6dd744ef1e685be363ce9813d49f7fa19"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-apple-darwin14-gcc4.tar.gz",
         "c9520ef62e04208576bf13c50a89ddf3c59b8b73119aae8b7bc5630e916b4f19"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-apple-darwin14-gcc7.tar.gz",
         "56b145b4d1e86ca79dcb09bd1d8b35d32053149a532bb1019c4ef420c13171bb"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-apple-darwin14-gcc8.tar.gz",
         "8380ed0e7f2ce4e8e7b382aed41855ece7865e03c76a5adb2dcfce116e312dd1"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-gnu-gcc4.tar.gz",
         "37d97bff1c43e1e4c8ace825d0bd171a50439b32c913437cef8b720375ad08dc"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-gnu-gcc7.tar.gz",
         "a41e8dd20c4f68021ca857245912a4d0c5a26a4f149985ab9e82ddf4d76997e1"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-gnu-gcc8.tar.gz",
         "39333e2fc84a242d632a1604fd042679e5faed6ea3ba311a1896f1b8f76eab79"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-musl-gcc4.tar.gz",
         "e3a2699920fd1746ad45bd4a8f5589305d22d30c5a5da44ada23bb5662139bc2"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-musl-gcc7.tar.gz",
         "828284dff268dd5279a5546ec31abcf087953546d55d4160de8a0e27dd323f52"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-linux-musl-gcc8.tar.gz",
         "83710ec095df0496de04a51d3f89edf68a925f1d126d11db39f0dd64d077b1e8"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-unknown-freebsd11.1-gcc4.tar.gz",
         "84d5cfae325cd6b28c40c99e37b84cb0edef35d137e527da1d7aadd79848b886"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-unknown-freebsd11.1-gcc7.tar.gz",
         "d48fb50fc088d1a97dd8d270b164394dcc15b927b9534f59c6e806ee41536812"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-unknown-freebsd11.1-gcc8.tar.gz",
         "53170e3ea896fb1afe4457a12c6ab873fc658dc8d8e0534d37d64b598ded1aa2"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc4)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-w64-mingw32-gcc4.tar.gz",
         "f1002f31916a85bd065e1573920516a97e66ca50ebadc9d56d894f2e694a966a"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc7)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-w64-mingw32-gcc7.tar.gz",
         "d37c26428d2db568fddab26189a98c4cce51702008d95db036aaca9ee3361602"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc8)) =>
        ("$bin_prefix/Openspecfun.v0.5.3.x86_64-w64-mingw32-gcc8.tar.gz",
         "266608d0392a69179db6f2e1bfca782d634203a34cb56adb256d31b91a3362fc"),
)
unsatisfied = any(p->!satisfied(p; verbose=verbose), products)
to_download = choose_download(download_info, platform_key_abi())
if to_download !== nothing && !forcecompile
    if !isinstalled(to_download...; prefix=prefix)
        install(to_download...; prefix=prefix, force=true, verbose=verbose)
        unsatisfied = any(p->!satisfied(p; verbose=verbose), products)
    end
    if unsatisfied
        rm(joinpath(@__DIR__, "usr", "lib"); force=true, recursive=true)
    end
end
if unsatisfied || forcecompile
    include("scratch.jl")
else
    write_deps_file(joinpath(@__DIR__, "deps.jl"), products; verbose=verbose)
end
