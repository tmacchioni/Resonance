"""Release preflight checks shared by CI and local maintainers."""
import re

def validate_release(config, tag, repository):
    version = config.get('version', '')
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Config/Release.json must declare a stable version such as 1.2.0.')
    expected = f'v{version}'
    if tag != expected:
        raise ValueError(
            f'Tag {tag!r} points to a commit declaring version {version!r}; expected tag {expected!r}. '
            'Update version and build in Config/Release.json, commit and push that change, '
            'then create the matching tag on that commit. Re-running this job keeps the same tagged files.'
        )
    if repository != config.get('repository'):
        raise ValueError('RELEASE_REPOSITORY must match Config/Release.json; configure the repository before releasing a fork.')
    if not isinstance(config.get('build'), str) or not re.fullmatch(r'[1-9]\d*', config['build']):
        raise ValueError('Config/Release.json must declare a positive numeric build, increasing for every release.')
