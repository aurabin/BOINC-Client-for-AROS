# Repository licensing

This repository combines independently written project code with patches to AROS. The following terms apply by component.

| Component | Applicable license |
| --- | --- |
| Original project code and documentation, including the Windows launcher scripts and setup program | [MIT](LICENSE) |
| Standalone guest tools `ChatGPT.c`, `DriverScan.c`, and `SystemUpdates.c` | [MIT](LICENSE) for the original project source. AROS SDK headers and libraries carry their respective upstream terms. |
| [HDToolBox patch](windows-launcher/guest/hdtoolbox-abiv11.patch) | [AROS Public License 1.1](LICENSES/AROS-Public-License-1.1.txt) for the AROS-derived patch content and modified AROS files. Upstream paths are `workbench/tools/HDToolBox/gui.c` and `workbench/tools/HDToolBox/harddisks.c`. |
| [Wanderer patch](windows-launcher/guest/wanderer-windows-fullscreen.patch) | [AROS Public License 1.1](LICENSES/AROS-Public-License-1.1.txt) for the AROS-derived patch content and modified AROS file. The upstream path is `workbench/system/Wanderer/wanderer.c`. |
| Other third-party components | The license and copyright notices supplied with the component, including any notices that apply to individual files. |

The patches target [AROS ABIv11 2026.09](https://github.com/deadwood2/AROS/tree/ABIv11_2026.09). The original affected files credit the AROS Development Team. Preserve those notices when applying the patches. The included AROS license text comes from the [tagged upstream LICENSE](https://github.com/deadwood2/AROS/blob/ABIv11_2026.09/LICENSE).

## Distribution

The Wizard can download an AROS ISO and launch it through QEMU. A downloaded ISO carries the licenses supplied with that distribution. QEMU carries its own upstream terms. When redistributing an ISO, QEMU, or an SDK alongside the Wizard, include the applicable notices and meet each component's source distribution requirements.

For binaries built from the patched AROS files, follow APL §§ 3.1–3.6, including the requirements for making covered source and changes available and telling recipients where to find them. APL § 3.7 allows the AROS components to be distributed together with the MIT components under their respective terms.
