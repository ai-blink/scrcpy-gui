"""Current macro UX plus picker-state and persisted management regression."""
import runpy
from pathlib import Path
for suite in ['emulator_macro_ux.py','emulator_macro_pickers.py','emulator_macro_management.py']:
 runpy.run_path(str(Path(__file__).with_name(suite)),run_name='__main__')
