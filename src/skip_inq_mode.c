// SPDX-License-Identifier: GPL-2.0
/*
 * skip_inq_mode: kretprobe module to skip two HCI commands that UWE5621DS
 * (Marlin3E) does not support during kernel init:
 *   1. HCI_OP_WRITE_INQUIRY_MODE    (0x0C45) — chip ignores → timeout
 *   2. HCI_OP_WRITE_DEF_LINK_POLICY (0x080F) — chip returns EINVAL
 *
 * opcode = (OGF << 10) | OCF, so:
 *   0x0C45 = (0x03 << 10) | 0x0045  Host Controller & Baseband commands
 *   0x080F = (0x02 << 10) | 0x000F  Link Control commands
 * Do NOT swap them: 0x0C45 is NOT "Write Default Link Policy".
 *
 * Kernel 6.18+ removed HCI_QUIRK_NO_PARK_LINK_POLICY and CONFIG_BT_DEBUGFS
 * is typically not enabled in ophub builds. This module uses kretprobe to
 * intercept and override the return values of the relevant init functions.
 *
 * Build: make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
 * Load:  modprobe bluetooth && insmod skip_inq_mode.ko
 */
#include <linux/module.h>
#include <linux/kprobes.h>

static struct kretprobe rp_inquiry;
static struct kretprobe rp_link_policy;

static int rp_handler(struct kretprobe_instance *ri, struct pt_regs *regs)
{
    regs_set_return_value(regs, 0);
    return 0;
}

static int __init skip_inq_init(void)
{
    int ret;

    rp_inquiry.handler = rp_handler;
    rp_inquiry.kp.symbol_name = "hci_write_inquiry_mode_sync";
    rp_inquiry.maxactive = 20;
    ret = register_kretprobe(&rp_inquiry);
    if (ret < 0) {
        pr_err("skip_inq_mode: cannot probe inquiry_mode: %d\n", ret);
        return ret;
    }

    rp_link_policy.handler = rp_handler;
    rp_link_policy.kp.symbol_name = "hci_setup_link_policy_sync";
    rp_link_policy.maxactive = 20;
    ret = register_kretprobe(&rp_link_policy);
    if (ret < 0) {
        pr_err("skip_inq_mode: cannot probe link_policy: %d\n", ret);
        unregister_kretprobe(&rp_inquiry);
        return ret;
    }

    pr_info("skip_inq_mode: both probes active (inquiry_mode + link_policy)\n");
    return 0;
}

static void __exit skip_inq_exit(void)
{
    unregister_kretprobe(&rp_link_policy);
    unregister_kretprobe(&rp_inquiry);
    pr_info("skip_inq_mode: probes removed\n");
}

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Skip unsupported HCI commands for UWE5621DS BT (Marlin3E)");
MODULE_AUTHOR("QwenWork agent");
module_init(skip_inq_init);
module_exit(skip_inq_exit);
