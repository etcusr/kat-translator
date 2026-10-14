"""Build variants share model data; only runtime binaries and packaging differ."""
def profile(name):
    common={'modelPackage':'assets/catalogs/index-mlx-package.json'}
    variants={
        'modern':{'minimum':'27.0','deployment':'26.2','suffix':'','runtime':'index-mlx'},
        'macos15':{'minimum':'15.0','deployment':'15.0','suffix':'-macos15-26','runtime':'index-mlx-macos15'},
    }
    if name not in variants:raise ValueError('Unknown Mac build profile: '+name)
    return common | variants[name]
