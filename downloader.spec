# PyInstaller spec for ACL Downloader
# To build: pyinstaller -y downloader.spec

import sys
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.building.datastruct import Tree
import os

block_cipher = None

hiddenimports = (
    collect_submodules('requests')
    + collect_submodules('yt_dlp')
    + collect_submodules('bs4')
    + collect_submodules('mutagen')
    + collect_submodules('cryptography')
    + collect_submodules('psutil')
)

extra_datas = []
if os.path.isdir('bin'):
    extra_datas.append(Tree('bin', prefix='bin'))

analysis = Analysis([
    'app.py',
],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False)

pyz = PYZ(analysis.pure, analysis.zipped_data, cipher=block_cipher)

# Platform-specific packaging: app bundle on macOS, folder on others
app_name = os.environ.get('APP_NAME', 'Coco Downloader')
exe_slug = os.environ.get('APP_SLUG', 'coco-downloader')

# Build EXE first for all platforms
exe = EXE(pyz,
          analysis.scripts,
          [],
          exclude_binaries=True,
          name=exe_slug,
          debug=False,
          bootloader_ignore_signals=False,
          strip=False,
          upx=True,
          console=False)

if sys.platform == 'darwin':
    bundle_id = os.environ.get('BUNDLE_ID', 'com.acl.downloader')
    app = BUNDLE(exe,
                 name=f'{app_name}.app',
                 icon=None,
                 bundle_identifier=bundle_id,
                 info_plist=None)
    coll = COLLECT(app,
                   analysis.binaries,
                   analysis.zipfiles,
                   analysis.datas,
                   *extra_datas,
                   strip=False,
                   upx=True,
                   name=exe_slug)
else:
    coll = COLLECT(exe,
                   analysis.binaries,
                   analysis.zipfiles,
                   analysis.datas,
                   *extra_datas,
                   strip=False,
                   upx=True,
                   name=exe_slug)
