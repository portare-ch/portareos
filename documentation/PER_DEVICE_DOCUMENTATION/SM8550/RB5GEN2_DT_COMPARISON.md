# The QCS8550 RB5 Gen 2 device tree against the Nova's

Linux 7.3 adds Qualcomm's own QCS8550 board, the RB5 Gen 2
(`arch/arm64/boot/dts/qcom/qcs8550-rb5gen2.dts`, 1573 lines, read from
mainline at 7.3-rc6 on 2026-10-06, with its `qcs8550.dtsi`). It is the
closest thing to a canonical QCS8550 setup, so it was compared node by node
with the Nova chain: `qcs8550-retroidpocket-rpnova.dts` includes
`qcs8550-retroidpocket-rp6.dts` includes `qcs8550-ayn-common.dtsi`, all in
`projects/PortareOS/devices/SM8550/linux/dts/qcom/`. Both boards sit on
`sm8550.dtsi`; the Nova build also patches that file (0001 PCIe PHY on the
root port, 1049 PCIe suspend OPP, 1051 lowest GPU OPP, 1071 MDSS regdma, 0120
gpu_cc, 20260424 gcc CX power domain) and the RB5 runs it stock.

Line references: "RB5 nnn" is the RB5 dts; "common nnn", "rp6 nnn", "nova
nnn" are the three Nova files, at the tree state of 2026-10-06.

## Result

Nothing in the RB5 board file is worth taking. Every node both boards set
(UFS, USB PHYs and repeater supplies, pcie0_phy, the WCN7850 PMU LDOs and the
wifi and Bluetooth supplies, SD card detect, pinctrl and supplies, the zap
shader path, DSI and DP supplies, clocks, the reserved GPIO range, the
volume-up wake key, pon) is identical or the Nova's is a superset. What the
RB5 adds is dev-board hardware: pm8010 and pmr735d PMICs, modem and IPA, two
TC9563 PCIe switches with Wi-Fi behind the second, an LT9611 HDMI bridge, an
nb7vpq904m USB retimer, CAN, status LEDs.

Four things the comparison turned up are on the Nova's own side, and each
was checked against the files on 2026-10-06:

- **WCN7850 rail windows.** The PMU's `vddaon` is `s2g` and `vdd` is `s5g`
  on both boards, but the software windows are crossed: RB5 allows s2g
  0.50-1.05 V and s5g 0.80-1.00 V, the Nova s2g 0.80-1.00 V and s5g
  0.50-1.00 V. The PMU driver only enables these rails and sets no voltage,
  so the window matters only as the floor RPMh may settle to. Which pair is
  right is not decidable from the files; the Wi-Fi works with ours.
- **SD card CX vote.** The Nova replaces `sdhc_2` with the downstream
  driver's node for SDR104 (rp6 395-494, reason in its comment). That node
  carries no `power-domains` and no `required-opps`, so unlike the stock
  node nothing in the device tree raises CX for the 202 MHz clock. It runs
  at 85 MB/s today, so something else holds CX while a card is busy; worth
  knowing if SD ever misbehaves at idle.
- **Sound card name.** The card still reports `model = "AYN-Odin2"`. That is
  not a leftover to fix: the kernel loads the topology blob by card name
  (`AYN-Odin2-tplg.bin`, see `AUDIO_SAMPLE_RATES.md`), and
  `030-suspend_mode` and `extra-firmware` key on it too. Renaming it means
  renaming all of those together.
- **SW_CTRL.** RB5 hands the WCN7850's SW_CTRL line (gpio82) to the PMU
  driver as `swctrl-gpios`; the Nova pins it down in `bt_default` and does
  not. The 7.2 driver (`pwrseq-qcom-wcn.c`) never reads that property, so
  the two are equivalent today; it is the binding's documented place for
  the line if a later driver starts using it.

The thermal trips the Nova adds have no `cooling-maps`, which is deliberate:
the fan is driven from user space (`fancontrol`), not by the kernel's
thermal framework.

## 1. PMICs and regulators

PMIC includes:

| RB5 (lines 11-20) | Nova (common 9-15) | Difference |
|---|---|---|
| qcs8550, pm8010, pm8550, pm8550b, pm8550ve (`PMK8550VE_SID 5`), pm8550vs, pmk8550, pmr735d_a, pmr735d_b | qcs8550, pm8550, pm8550b, pm8550ve (SID 5), pm8550vs, pmk8550 | Nova does not include pm8010 (two camera-type PMICs, RB5 `regulators-6` "m" 755-820 and `regulators-7` "n" 822-887) nor pmr735d_a/b (RB5 declares no regulators for them in the board file). |

`regulators-0` (pm8550, pmic-id "b"; RB5 297-485, common 572-752). Input supplies are the same rails under different labels (RB5 `vreg_s6g_1p86`/`vreg_s4g_1p25` = Nova `vreg_s6g_1p8`/`vreg_s4g_1p3`).

| Rail | RB5 min-max uV | Nova min-max uV | Difference |
|---|---|---|---|
| bob1 | 3296000-3960000 (314-319) | 3296000-3960000 (589-602) | Nova adds `regulator-state-mem { on-in-suspend; mode LPM }`. |
| bob2 | 2720000-3960000 (321-326) | 2720000-3960000 (604-617) | Nova adds `regulator-state-mem { off-in-suspend }`. |
| l1b | 1710000-1950000 (328-333) | not declared | RB5 only. |
| l2b | 2900000-3544000 (335-340) | 3008000 fixed (619-627) | Nova fixed + set-load. |
| l5b | 3000000-3300000 (342-347) | 3104000 fixed (629-637) | Nova fixed + set-load. Feeds eUSB2 repeater vdd3 on both. |
| l6b | 1700000-3300000 (349-354) | 1800000-3008000 (639-647) | Nova narrower + set-load. |
| l7b | 1700000-3300000 (356-361) | 1800000-3008000 (649-654) | Nova narrower, no set-load. |
| l8b (SD vqmmc) | 1800000-3008000 (422-427) | 1800000-3008000 (656-664) | Same range; Nova adds set-load. |
| l9b (SD vmmc) | 2960000-3008000 (429-434) | 2960000-3008000 (666-674) | Same range; Nova adds set-load. |
| l11b | 1100000-1300000 (436-441) | 1200000-1504000 (676-684) | Different window. |
| l12b | 1710000-1950000 (443-448) | 1800000 fixed (686-694) | Nova fixed + set-load. |
| l13b | 2700000-3300000 (450-455) | 3000000 fixed (696-704) | Nova fixed + set-load. |
| l14b | 3200000-3300000, `regulator-always-on` (457-463) | 3200000 fixed, set-load, not always-on (706-714) | RB5 keeps l14b on; it feeds its LT9611 HDMI bridge regulators (160, 170) and CAN (1382-1383). Nova has none of those consumers. |
| l15b | 1760000-1800000 (465-470) | 1800000 fixed, set-load, `regulator-state-mem { on-in-suspend; LPM }` (716-731) | Nova keeps it on in suspend (codec + panel 1.8 V per comment 725-726). RB5 uses it for WCN vddio, repeater vdd18, WSA speakers, retimer vcc. |
| l16b | 2000000-3400000 (472-477) | 2800000 fixed (733-741) | Nova fixed + set-load. |
| l17b (UFS vcc) | 2400000-3300000 (479-484) | 2504000 fixed (743-751) | Nova fixed + set-load. |

Other PMICs:

| Node | RB5 | Nova | Difference |
|---|---|---|---|
| regulators-1 "c" (pm8550vs) | supplies l1/l2/l3 + vdd-s1/s4/s6 = vph_pwr; l3c 835000-912000 (487-504) | supplies l1/l2/l3 only; l3c 880000-912000 + set-load (754-771) | Nova omits the `vdd-sN-supply` lines and raises l3c min. |
| regulators-2 "d" | l1d 825000-958000, l2d 675000-808000, s4d 572000-988000, s5d 572000-988000 (506-542) | l1d 880000-920000 + set-load only (773-790) | Nova declares no l2d, s4d, s5d. |
| regulators-3 "e" | l1e 831000-904000, l2e 870000-970000, l3e 1200000, s1e 532000-852000, s3e 716000-884000, s4e 870100-1152000, s5e 1010000-1120000, s6e 528000-904000 (544-612) | s4e 904000-984000, s5e 1010000-1120000, l1e 880000-912000, l2e 870000-970000, l3e 1200000; set-load on LDOs (792-845) | Nova declares no s1e, s3e, s6e. s4e window differs (RB5 wider). |
| regulators-4 "f" (pm8550ve) | l1f 866000-958000, l2f 866000-880000, l3f 830000-920000, s1f 516000-904000, s3f 688000-952000, s4f 300000-500000, s5f 716000-884000, s7f 516000-812000 (614-682) | s4f 300000-700000, l1f/l2f/l3f 880000-912000 + set-load (847-892) | Nova declares no s1f, s3f, s5f, s7f; s4f max 700000 vs 500000. |
| regulators-5 "g" | l1g 1140000-1260000, l3g 1200000, s1g 1172000-1388000, s2g 500000-1053200, s3g 532000-1148000, s4g 1172000-1800000, s5g 800000-1002600, s6g 1800000-2192000 (684-753) | l1g 1200000, l3g 1200000 (+set-load), s1g 1200000-1300000, s2g 800000-1000000, s3g 300000-1004000, s4g 1200000-1352000, s5g 500000-1004000, s6g 1800000-2000000 (894-969) | Same rails, different windows. WCN `vddaon` = s2g: RB5 min 500000, Nova min 800000. WCN `vdd` = s5g: RB5 min 800000, Nova min 500000. |
| regulators-6/7 "m"/"n" (pm8010) | 14 LDOs 755-887; `regulator-allow-set-load` + `allowed-modes LPM HPM` only on l1m, l2m, l1n, l2n (771-773, 781-783, 838-840, 848-850) | absent | RB5 is the only tree with pm8010. |

`regulator-allow-set-load`/`regulator-allowed-modes`: RB5 sets them on four pm8010 LDOs only (grep); every pm8550 b/c/d/e/f/g LDO is HPM with no load switching. Nova sets them on every LDO it declares in b, c, d, e, f, g (common 624-965). `regulator-always-on`/`boot-on`: RB5 `vph_pwr` (247-248) and `vreg_l14b_3p2` (462). Nova `vph_pwr` (480-481), `vdd_mcu_3v3` fixed regulator boot-on (470); no RPMh rail is always-on. Nova alone has `regulator-state-mem` blocks (bob1, bob2, l15b, vdd_fan_5v0 456-458).

Verdict: nothing to take. RB5's regulator windows are the reference-board defaults with no load switching; the only always-on rail it adds (l14b) exists for peripherals the Nova does not have. Worth checking: the s2g/s5g minimums differ between the two boards for the same WCN7850 supplies (RB5 s2g 500000/s5g 800000 vs Nova 800000/500000); the files alone do not say which is right.

## 2. RPMh power-domain votes

| Item | RB5 | Nova | Difference |
|---|---|---|---|
| `required-opps` / `power-domains` / `rpmhpd` in board files | none (grep over the dts: zero hits) | none in common/rpnova; rp6's replacement `sdhc_2` (rp6 415-494) has an `opp-table` with `opp-hz`, `opp-peak-kBps`, `opp-avg-kBps` but no `required-opps`, and the node has no `power-domains` | The stock `sdhc_2` (sm8550.dtsi 3605, 3622-3640) votes `rpmhpd RPMHPD_CX` with min_svs/low_svs/svs/svs_l1 per OPP; RB5 inherits that. Nova's downstream node drops the CX vote and the per-OPP levels entirely. |
| `opp-level` choices | inherited stock sm8550.dtsi | stock plus repository patches: 1049 adds a PCIe `opp-suspend` OPP (`opp-hz 1`, `required-opps low_svs`, `opp-peak-kBps 250000 1`), 1051 adds GPU `opp-124800000` at `LOW_SVS_D2`, 20260424 adds `power-domains = <&rpmhpd RPMHPD_CX>` to gcc | Nova's base dtsi has three vote changes RB5 does not carry. |

Verdict: nothing to take from RB5 (it makes no board-level votes). Worth checking on Nova's side: the downstream `sdhc_2` node has no `power-domains`/`required-opps`, so nothing in the device tree raises CX for SD at 202 MHz; whether the downstream driver votes by another path is not visible in these files.

## 3. ADSP and Q6APM audio

| Item | RB5 | Nova | Difference |
|---|---|---|---|
| `remoteproc_adsp` firmware | `qcom/sm8550/adsp.mbn`, `adsp_dtb.mbn` (1335-1339) | rp6 381-385 `qcom/sm8550/ayn/odin2/...`, overridden by nova 21-24 `qcom/sm8550/retroidpocket/rpnova/adsp.mbn`, `adsp_dtb.mbn` | Stock Qualcomm images vs device-dumped images. |
| ADSP memory | inherited: `adspslpi_mem` 0x9ea00000+0x4080000, `q6_adsp_dtb_mem` 0x9e980000+0x80000 (sm8550.dtsi 3152, qcs8550.dtsi 147-155) | identical, neither region deleted | Same. |
| `remoteproc_cdsp` | `qcom/sm8550/cdsp.mbn` (1341-1345) | common 1480-1484 `ayn/cdsp.mbn`, nova 26-29 `retroidpocket/rpnova/cdsp.mbn` | Path only. |
| `sound` compatible | `qcom,sm8550-sndcard`, `qcom,sm8450-sndcard` (252) | same (343) | Same. |
| `sound` model | `QCS8550-RB5Gen2` (253) | `AYN-Odin2` (353); not overridden in rp6 or nova | Nova card still reports the Odin 2 name. |
| `sound` clocks | none | `q6prmcc LPASS_CLK_ID_SEN_MI2S_IBIT`, `clock-names i2s_clk`, `assigned-clock-rates 1536000` (347-351), `pinctrl-0 lpi_i2s3_active` (344) | RB5 has no I2S path, so no card-level clock. |
| audio-routing | `SpkrLeft IN`->`WSA_SPK1 OUT`, `SpkrRight IN`->`WSA_SPK2 OUT`, `VA DMIC0/1`->`vdd-micb` (254-257) | `IN1_HPHL`/`IN2_HPHR`, `AMIC2`->`MIC BIAS2`, `TX SWR_INPUT1`->`ADC2_OUTPUT` (354-358), nothing for the amps | Different codecs. |
| Speaker link | `wsa-dai-link` "WSA Playback": cpu `q6apmbedai WSA_CODEC_DMA_RX_0`, codec `left_spkr, right_spkr, swr0 0, lpass_wsamacro 0`, platform `q6apm` (259-274) | `speaker-i2s-dai-link` "Primary MI2S Playback": cpu `q6apmbedai PRIMARY_MI2S_RX`, codec `spk_amp_l 0, spk_amp_r 0`, platform `q6apm` (360-374) | RB5: SoundWire WSA883x via wsamacro. Nova: I2S to AW88166. Nova's cpu DAI is `PRIMARY_MI2S_RX`, its clock `SEN_MI2S_IBIT`, its pins `i2s3_*` (lpass_tlmm 1044-1078, all `output-high`). |
| Capture link | `va-dai-link`: `lpass_vamacro 0` / `VA_CODEC_DMA_TX_0` (276-290) | `wcd-capture-dai-link`: `wcd938x 1, swr2 0, lpass_txmacro 0` / `TX_CODEC_DMA_TX_3` (392-406) | RB5 uses on-SoC DMICs via vamacro; Nova the WCD9385 headset codec. |
| Other links | none | `wcd-playback-dai-link` RX_CODEC_DMA_RX_0 (376-390), `dp0-dai-link` DISPLAY_PORT_RX_0 -> `mdss_dp0` (408-421) | Nova only. |
| `lpass_vamacro` | `pinctrl-0 dmic01_default`, `qcom,dmic-sample-rate 4800000`, `vdd-micb-supply l15b` (1011-1018) | `qcom,dmic-sample-rate 4800000` only (1080-1082) | Nova has no DMIC pins or micbias supply on vamacro. |
| `lpass_wsamacro` | used (264) | `status = "disabled"` (1084-1086) | Nova disables the unused macro. |
| SoundWire | `swr0` okay, two `sdw20217020400` speakers, reset tlmm 133, `vdd-1p8`/`vdd-io` l15b, `qcom,port-mapping` (1387-1417) | `swr1` codec@0,4 `rx-port-mapping 1 2 3 4 5`, `swr2` codec@0,3 `tx-port-mapping 2 2 3 4` (1507-1523) | Different buses, different devices. |
| Amps | n/a | `i2c_hub_2` 0x34/0x35 `awinic,aw88166`, reset tlmm 103/100, `awinic,audio-channel 0/1`, `awinic,sync-flag`, `firmware-name .../aw883xx_acf.bin` (common 1011-1029, nova 31-37) | Nova only. |

Canonical RB5 Q6APM card for reference: compatible `qcom,sm8550-sndcard`; each link has `link-name`, a `cpu` on `q6apmbedai <BE id>`, a `codec` list ending in the SoundWire controller and the LPASS macro, and `platform = <&q6apm>`; no clocks or pinctrl on the card node; routing from the codec widgets to the macro outputs.

Verdict: nothing to take for the I2S path (RB5 has none). Worth checking: the Nova card node still says `model = "AYN-Odin2"`, and the `PRIMARY_MI2S_RX` / `SEN_MI2S_IBIT` / `i2s3_*` naming mix has no RB5 counterpart to confirm against.

## 4. SD card (`sdhc_2`)

| Property | RB5 (1353-1367 + sm8550.dtsi 3590-3641) | Nova vendor node (common 1486-1501) | Nova effective node (rp6 412-494, downstream driver) |
|---|---|---|---|
| compatible | `qcom,sm8550-sdhci`, `qcom,sdhci-msm-v5` | same | `qcom,sdhci-msm-v5-downstream` |
| cd-gpios | `pm8550_gpios 12 ACTIVE_LOW` (1354) | same (1487) | same (465) |
| pinctrl | default `sdc2_default`+`sdc2_card_det_n`, sleep `sdc2_sleep`+`sdc2_card_det_n` (1356-1358) | same (1488-1490) | same (461-463) |
| `sdc2_card_det_n` pin state | gpio12 normal, power-source 1, bias-pull-up, input-enable (1258-1264) | same plus `output-disable` (1169-1176) | uses the common one |
| regulators | `vmmc-supply l9b`, `vqmmc-supply l8b` (1360-1361) | same (1491-1492) | `vdd-supply l9b`, `vdd-io-supply l8b` plus `qcom,vdd-voltage-level`, `qcom,vdd-io-voltage-level`, current levels (453-459) |
| bus-width | 4 (inherited 3613) | 4 (inherited) | 4 (422) |
| no-sdio / no-mmc | both (1363-1364) | both (1494-1495) | both (423-424) |
| max-sd-hs-hz | 37500000 (inherited 3614) | 37500000 (1493) | absent |
| DLL config | `qcom,dll-config 0x0007642c`, `qcom,ddr-config 0x80040868` (inherited 3603-3604) | `qcom,dll-config 0x0007442c` (1497), `sdhci-caps-mask <0x3 0x0>` (1498) | `qcom,dll-hsr-list 0x0007442C 0x0 0x10 0x090106C0 0x80040868` (436-437) |
| power-domains / OPP | `rpmhpd RPMHPD_CX`, OPPs 19.2/50/100/202 MHz with `required-opps` (inherited 3605-3640) | inherited | own `opp-table` 100/202 MHz with bandwidth only, no `required-opps`, no `power-domains` (451, 479-493) |
| clocks | iface, core, xo (inherited 3598-3601) | inherited | iface, core only (428-430) |
| interconnects | ICC tags ALWAYS / ACTIVE_ONLY (inherited 3608-3612) | inherited | tags 0, plus `qcom,msm-bus,*` vectors (441-449) |
| extra | - | - | `qcom,restore-after-cx-collapse`, `qcom,uses_level_shifter`, `qcom,dll_lock_bist_fail_wa`, `resets GCC_SDCC2_BCR`, `qos0/qos1` (425-427, 466-476) |

Properties present on RB5's effective node that Nova's effective node lacks: `power-domains`, `required-opps`, `max-sd-hs-hz`, `qcom,ddr-config`, the `xo` clock, ICC tags. Nova lacks nothing RB5 sets at board level; the board-level lines are the same.

Verdict: nothing to take at board level; both set identical cd-gpios, pinctrl, supplies and no-sdio/no-mmc. The differences are in the Nova's node replacement (rp6 395-411 explains why), see section 2 for the missing CX vote.

## 5. USB

| Item | RB5 | Nova | Difference |
|---|---|---|---|
| `pmic-glink` | compatible `qcom,sm8550-pmic-glink`, no `orientation-gpios` (111-114) | same compatible, `orientation-gpios = <&tlmm 11 GPIO_ACTIVE_HIGH>` (58-62) | RB5 gets orientation from the nb7vpq904m retimer; Nova from a GPIO. |
| connector | `usb-c-connector`, power-role dual, data-role dual (116-120) | same (64-68) | Same. |
| port@0 (HS) | `usb_1_dwc3_hs` (129) | `usb_1_dwc3_hs` (78) | Same. |
| port@1 (SS) | `redriver_usb_con_ss` on the retimer (137) | `usb_dp_qmpphy_out` directly (86) | RB5 has a retimer in the SS path. |
| port@2 (SBU) | `redriver_usb_con_sbu` (145) | `usb0_sbu_mux` (94), a `gpio-sbu-mux` with enable tlmm 140 low, select tlmm 141, `mode-switch`, `orientation-switch` (424-441) | Different SBU hardware. |
| retimer / mux | `i2c_hub_2` typec-mux@1c `onnn,nb7vpq904m`, `vcc-supply l15b`, `retimer-switch`, `orientation-switch`, three ports; `redriver_phy_con_ss` <- `usb_dp_qmpphy_out` with `data-lanes 0 1 2 3` (911-949, 1567-1569) | none; `usb_dp_qmpphy_out` -> `pmic_glink_ss_in` (1794-1796) | RB5 only. |
| `usb_1` | `status okay` only (1543-1545) | same (1768-1770) | Both inherit `usb-role-switch` (sm8550.dtsi 4582), no `dr_mode`, no `maximum-speed`, PDC wake IRQs 14/15/17 (4541-4543). |
| `usb_1_hsphy` | `vdd l1e`, `vdda12 l3e`, `phys pm8550b_eusb2_repeater` (1551-1558) | same (1776-1783) | Same. |
| `pm8550b_eusb2_repeater` | `vdd18 l15b`, `vdd3 l5b` (1301-1304) | same plus `qcom,tune-usb2-disc-thres 0x6`, `tune-usb2-amplitude 0xb`, `tune-usb2-preem 0x3` (1421-1427) | Nova carries eye-tuning values; RB5 uses defaults. |
| `usb_dp_qmpphy` | `vdda-phy l3e`, `vdda-pll l3f` (1560-1565) | same plus `mode-switch` (1785-1792) | `mode-switch` is already in sm8550.dtsi 4483; Nova's line is redundant. |
| wakeup on connector/typec | none | none | Same. |

Verdict: nothing to take. The RB5 USB graph differs only where it has a retimer; everything the two boards share (HS endpoint, PHY supplies, repeater supplies, role switch) is identical.

## 6. Wi-Fi / Bluetooth

| Item | RB5 | Nova | Difference |
|---|---|---|---|
| `wcn7850-pmu` pinctrl | `wlan_en`, `bt_default`, `sw_ctrl_default`, `pmk8550_sleep_clk` (296-298) | `wlan_en`, `bt_default`, `pmk8550_sleep_clk` (513-514); `bt_default` contains both gpio81 and gpio82 (1584-1597) | Same pins; Nova folds SW_CTRL into `bt_default`. |
| GPIOs | `wlan-enable tlmm 80`, `bt-enable tlmm 81`, `swctrl-gpios tlmm 82` (300-302) | `wlan-enable tlmm 80`, `bt-enable tlmm 81`; no `swctrl-gpios` (516-517) | Nova configures gpio82 as a pull-down pin but does not hand it to the PMU driver. |
| PMU supplies | `vdd s5g`, `vddio l15b`, `vddaon s2g`, `vdddig s4e`, `vddrfa1p2 s4g`, `vddrfa1p8 s6g` (304-309) | same six plus `vddio1p2-supply = <&vreg_l3g_1p2>` (519-525) | Nova adds `vddio1p2`. |
| PMU LDOs | ldo0-ldo9, `vreg_pmu_rfa_cmn` .. `vreg_pmu_pcie_1p8` (311-351) | identical (527-567) | Same. |
| `pcie0` | `vddpe-3v3-supply pcie_upd_3p3`, `wake-gpios tlmm 96 ACTIVE_HIGH`, `perst-gpios tlmm 94 ACTIVE_LOW`, `pinctrl pcie0_default_state`, `iommu-map` for a TC9563 switch, `/delete-property/ msi-map` (1045-1067) | `pinctrl pcie0_default_state` only (1122-1127) | RB5 keeps wake/perst on the controller (old binding) and has a PCIe switch on pcie0. |
| root port | `pcie0_port0` holds a `pci1179,0623` switch (1076-1146); Wi-Fi is on **pcie1** behind a second switch: `pcie1_port0/pcie@0,0/pcie@2,0/wifi@0` (1178-1247) | `pcieport0`: `wake-gpios tlmm 96 ACTIVE_LOW` (comment 1130-1131), `reset-gpios tlmm 94 ACTIVE_LOW`, `wifi@0` directly (1129-1149) | Nova uses the root-port binding and inverts WAKE# polarity relative to RB5. |
| `wifi@0` | `compatible pci17cb,1107`, `reg <0x40000 ...>`, 9 `vdd*-supply` from the PMU LDOs (1222-1235) | `pci17cb,1107`, `reg <0x10000 ...>`, same 9 supplies (1135-1147) | Same supplies; `reg` differs with bus position. |
| `qcom,ath12k-calibration-variant` | none | none | Neither. |
| wifi `firmware-name` | none | none | Neither. |
| `pcie0_phy` | `vdda-phy l1e`, `vdda-pll l3e` (1069-1074) | same (1151-1156) | Same. |
| `uart14` bluetooth | `qcom,wcn7850-bt`, 7 supplies `vddrfacmn` .. `vddrfa1p8` (1509-1523) | same 7 supplies plus `max-speed = <3200000>` (1713-1729) | Nova sets the UART speed. |
| LEDs | `blue:bt-power` trigger `bluetooth-power`, `yellow:wlan` trigger `phy0tx` (92-108) | none | RB5 only. |

Verdict: nothing to take. Shared properties are identical or Nova's are a superset (`vddio1p2`, `max-speed`). Worth checking: RB5 passes `swctrl-gpios` (gpio82) to the PMU, Nova only pins it down; and RB5 has `wake-gpios` ACTIVE_HIGH where Nova changed it to ACTIVE_LOW with a stated reason.

## 7. Wake sources

| Item | RB5 | Nova | Difference |
|---|---|---|---|
| gpio-keys volume-up | `linux,can-disable`, `wakeup-source`, debounce 15, `pm8550_gpios 6` (49-56) | same (48-55) | Same. |
| paddles | n/a | rp6 137-149, no `wakeup-source` | Nova only. |
| `pon_pwrkey` / `pon_resin` | okay; resin `KEY_VOLUMEDOWN` (1317-1325) | same (1462-1470) | Same. |
| `wakeup-event-action` | none | none | Neither. |
| `interrupts-extended` on `&pdc` in board files | none; the two uses are `tlmm 40` (LT9611, 961) and `tlmm 55` (CAN, 1379) | none; `tlmm 15` touch (rp6 358-359), `tlmm 13` fan (111-112) via `interrupt-parent` | Neither board file adds PDC wake interrupts; both inherit the SoC ones (adsp `pdc 6` 3134, usb `pdc 14/15/17` 4541-4543, tsens). |
| `wakeup-source` on uart14 / connector / pmic-glink | none | none | Neither. |

Verdict: nothing. The only board-level wake source on either tree is the volume-up key, configured identically.

## 8. reserved-memory

Both include `qcs8550.dtsi`, which deletes the sm8550 `reserved_memory` and defines 22 regions (qcs8550.dtsi 59-160). RB5 makes no changes. Nova:

Deleted by Nova (common 17-24), kept by RB5:

| Region | Address | Size |
|---|---|---|
| `aop_image_mem` | 0x81c00000 | 0x60000 |
| `aop_config_mem` | 0x81c80000 | 0x20000 |
| `camera_mem` | 0x9b300000 | 0x800000 |
| `ipa_fw_mem` | 0x9b080000 | 0x10000 |
| `ipa_gsi_mem` | 0x9b090000 | 0xa000 |
| `mpss_dsm_mem` | 0xd4d00000 | 0x3300000 |
| `mpss_mem` | 0x8a800000 | 0x10800000 |
| `q6_mpss_dtb_mem` | 0x9b000000 | 0x80000 |

Nova also deletes `remoteproc_mpss` (common 26); RB5 enables it with `modem.mbn`/`modem_dtb.mbn` (1347-1351) and enables `ipa` with `ipa_fws.mbn` (1001-1005).

Added by Nova (common 118-204), absent on RB5:

| Region | Address | Size |
|---|---|---|
| `hyp_mem` | 0x80000000 | 0xa00000 |
| `cpusys_vm_mem` | 0x80a00000 | 0x400000 |
| `hyp_tags_mem` | 0x80e00000 | 0x3d0000 |
| `hyp_tags_reserved_mem` | 0x811d0000 | 0x30000 |
| `xbl_dt_log_merged_mem` | 0x81a00000 | 0x260000 |
| `aop_config_merged_mem` | 0x81c80000 | 0x74000 (replaces the deleted 0x20000 `aop_config_mem`) |
| `chipinfo_mem` | 0x81cf4000 | 0x1000 |
| `global_sync_mem` | 0x82600000 | 0x100000 |
| `tz_stat_mem` | 0x82700000 | 0x100000 |
| `splash_region` | 0xb8000000 | 0x2b00000 (`label = "cont_splash_region"`) |
| `xbl_sc_mem` | 0xd8100000 | 0x40000 |
| `cpucp_fw_mem` | 0xd8140000 | 0x1c0000 |
| `qtee_mem` | 0xd8300000 | 0x500000 |
| `hwfence_shbuf` | 0xe6440000 | 0x2dd000 |
| `hyp_ext_tags_mem` | 0xfce00000 | 0x2900000 |
| `hyp_ext_reserved_mem` | 0xff700000 | 0x100000 |
| `llcc_lpi_mem` | 0xff800000 | 0x600000 |

Unchanged on both: `aop_cmd_db_mem`, `smem_mem`, `adsp_mhi_mem`, `gpu_micro_code_mem`, `spss_region_mem`, `spu_secure_shared_memory_mem`, `video_mem`, `cvp_mem`, `cdsp_mem`, `q6_cdsp_dtb_mem`, `q6_adsp_dtb_mem`, `adspslpi_mem`.

Verdict: nothing to take. RB5 relies on the qcs8550.dtsi comment (17-38) that UEFI/ESRT reserves the firmware regions at runtime and lists none itself; Nova lists them explicitly. The deletions on Nova are all modem/IPA/camera, which RB5 has and Nova does not.

## 9. Everything else RB5 has that Nova lacks

| Item | RB5 | Nova | Applies to a handheld? |
|---|---|---|---|
| Thermal zones | none added; stock sm8550.dtsi zones (6119-7173, cpu passive/critical trips, GPU `#cooling-cells` 2863) | adds `trips` to cpuss0-3, cpu7-top, gpuss-0..7 at 50-80 C (206-340) with `polling-delay 200`; no `cooling-maps` anywhere in the three files (grep); `pwm_fan` has `#cooling-cells` (115) but nothing maps to it | Nothing from RB5 to take; Nova's extra trips drive nothing in these files. |
| ADC channels / adc-tm | none | none | Neither declares PMIC ADC channels. |
| cpufreq / interconnect | none at board level | none except the downstream `sdhc_2` ICC lines | Nothing. |
| UFS | `reset-gpios tlmm 210`, `vcc l17b` 1300000 uA, `vccq l1g` 1200000 uA, `vdd-hba l3g`; phy `vdda-phy l1d`, `vdda-pll l3e` (1525-1541) | identical (1750-1766) | Same. Nova also disables `ice` (1036-1038, comment cites #505); RB5 leaves it stock. |
| GPU zap shader | `&gpu_zap_shader { firmware-name = "qcom/sm8550/a740_zap.mbn" }` (902-904) | `&gpu { zap-shader { firmware-name = "qcom/sm8550/a740_zap.mbn" } }` (983-985) | Same path, different spelling (label vs nested node). |
| `firmware-name` paths | all stock `qcom/sm8550/*.mbn` (adsp, cdsp, modem, ipa, zap) | adsp/cdsp under `qcom/sm8550/retroidpocket/rpnova/`, amp `aw883xx_acf.bin`, zap stock | Nova uses device-dumped DSP images. |
| Display | `mdss_dsi0` -> LT9611UXC HDMI bridge on bit-banged I2C (72-79, 952-991, 1024-1039), `mdss_dp0` okay (1041-1043) | `mdss_dsi0` panel `il97680a,rpnova` (nova 39-50; rp6 162-199), `mdss_dp0` okay with `sound-name-prefix` (1092-1095) | Same DSI/DP enables; different sink. |
| `mdss_dsi0` `vdda-supply` / phy `vdds-supply` | l3e / l1e (1025, 1036) | l3e / l1e (rp6 163, 197) | Same. |
| `tlmm gpio-reserved-ranges` | `<32 8>` (1422) | `<32 8>` (1526) | Same. |
| `sleep_clk` / `xo_board` | 32764 / 76800000 (1369-1371, 1571-1573) | same (1503-1505, 1798-1800) | Same. |
| `pm8550_pwm` | three green status LEDs led@1-3 (1267-1299) | RGB `power_led` red@1/green@2/blue@3 (1187-1212); channel 3 also used by `pwm_fan` via `pm8550_pwm 3 40000` (105) | Different use of the same PWM channels. |
| Peripherals absent on Nova | CAN mcp2518fd on spi11 (1373-1385), two TC9563 PCIe switches, pcie1 (1148-1176), LEDs (81-109), ipa, modem, pm8010, i2c_hub_4 (993-995) | - | Dev-board hardware, not applicable. |

Verdict: nothing to take. Every shared SoC-level setting (UFS, zap shader path, DSI/DP supplies, clocks, reserved GPIO range) is already identical; the rest of RB5's additions are for hardware the Nova does not have. Worth checking on Nova's own side only: the added thermal trips have no cooling-maps in these files, and the card `model` string is still the Odin 2's.
