"""Build variants share model data; only runtime binaries and packaging differ."""
def profile(name, store=False):
    # Direct profiles use pinned python-build-standalone; Store uses CPython of the same
    # version built without TLS extensions. Neither depends on a Homebrew Python upgrade.
    common={'modelPackage':'assets/catalogs/index-mlx-package.json','python':'Dependencies/build/macos15/StandalonePython/python'}
    if store:
        common['python']='Dependencies/build/macos-store-python/3.11.17-no-tls-v1/python'
    variants={
        'modern':{'minimum':'27.0','deployment':'26.2','suffix':'','runtime':'index-mlx'},
        'macos15':{'minimum':'15.0','deployment':'15.0','suffix':'-macos15-26','runtime':'index-mlx-macos15'},
    }
    if name not in variants:raise ValueError('Unknown Mac build profile: '+name)
    return common | variants[name]
