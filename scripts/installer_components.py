"""Pin Installer to the payload's application path, including nested Sparkle bundles."""

def pin_components(components):
    if not isinstance(components, list) or len(components) != 1:
        raise ValueError('Expected exactly one top-level application bundle')
    if components[0].get('RootRelativeBundlePath') != 'Applications/Resonance.app':
        raise ValueError('Installer payload must install Applications/Resonance.app')
    def pin(bundle):
        bundle['BundleIsRelocatable'] = False
        for child in bundle.get('ChildBundles', []): pin(child)
    for component in components: pin(component)
    return components
