/*
 * (C) Copyright 2016 Nexell
 * Youngbok, Park <park@nexell.co.kr>
 *
 * SPDX-License-Identifier:      GPL-2.0+
 */

#include <common.h>
#include <dm.h>
#include <dwmmc.h>
#include <asm/arch/nexell.h>
#include <asm/arch/clk.h>
#include <asm/arch/reset.h>
#include <asm/arch/nx_gpio.h>
#include <asm/arch/tieoff.h>
#include <asm-generic/errno.h>
#include <fdtdec.h>
#include <libfdt.h>

#define DWMCI_CLKSEL			0x09C
#define DWMCI_SHIFT_0			0x0
#define DWMCI_SHIFT_1			0x1
#define DWMCI_SHIFT_2			0x2
#define DWMCI_SHIFT_3			0x3
#define DWMCI_SET_SAMPLE_CLK(x)	(x)
#define DWMCI_SET_DRV_CLK(x)	((x) << 16)
#define DWMCI_SET_DIV_RATIO(x)	((x) << 24)

#define DWMCI_CLKCTRL			0x114

#define NX_MMC_CLK_DELAY(x, y, a, b)	(((x & 0xFF) << 0) |\
					((y & 0x03) << 16) |\
					((a & 0xFF) << 8)  |\
					((b & 0x03) << 24))
#define NX_MMC_MIN_CLOCK			400000

DECLARE_GLOBAL_DATA_PTR;

struct nexell_dwmmc_priv {
	int drive_delay;
	int drive_shift;
	int sample_delay;
	int sample_shift;
	struct dwmci_host host;
};

static unsigned int dw_mci_get_clk(struct dwmci_host *host, uint freq)
{
	struct clk *clk;
	int index = host->dev_index;
	char name[50] = {0, };

	snprintf(name, sizeof(name), "%s.%d", DEV_NAME_SDHC, index);
	clk = clk_get((const char *)name);
	if (!clk)
		return 0;

	return clk_get_rate(clk)/2;
}

static unsigned long dw_mci_set_clk(int dev_index, unsigned  rate)
{
	struct clk *clk;
	char name[50];

	snprintf(name, sizeof(name), "%s.%d", DEV_NAME_SDHC, dev_index);
	clk = clk_get((const char *)name);
	if (!clk)
		return 0;

	clk_disable(clk);
	rate = clk_set_rate(clk, rate);
	clk_enable(clk);

	return rate;
}

static void dw_mci_clksel(struct dwmci_host *host)
{
	u32 val;

	val = DWMCI_SET_SAMPLE_CLK(DWMCI_SHIFT_0) |
		DWMCI_SET_DRV_CLK(DWMCI_SHIFT_0) | DWMCI_SET_DIV_RATIO(3);

	dwmci_writel(host, DWMCI_CLKSEL, val);
}

static void dw_mci_clk_delay(struct nexell_dwmmc_priv *priv)
{
	int val;
	struct dwmci_host *host = &priv->host;

	val = NX_MMC_CLK_DELAY(priv->drive_delay, priv->drive_shift,
			       priv->sample_delay, priv->sample_shift);
	writel(val, (host->ioaddr + DWMCI_CLKCTRL));
}

static void dw_mci_reset(int ch)
{
	int rst_id = RESET_ID_SDMMC0 + ch;

	nx_rstcon_setrst(rst_id, 0);
	nx_rstcon_setrst(rst_id, 1);
}

static int nexell_dwmmc_ofdata_to_platdata(struct udevice *dev)
{
	struct nexell_dwmmc_priv *priv = dev_get_priv(dev);
	struct dwmci_host *host = &priv->host;

	host->name = dev->name;
	host->ioaddr = (void *)dev_get_addr(dev);
	host->buswidth = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					"nexell,bus-width", 4);
	host->get_mmc_clk = dw_mci_get_clk;
	host->clksel = dw_mci_clksel;
	host->priv = dev;
	host->dev_index = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					 "index", -1);
	if (host->dev_index == -1) {
		printf("fail to get index value\n");
		return -EINVAL;
	}

	priv->drive_delay = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					   "nexell,drive_dly", 0);
	priv->drive_shift = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					   "nexell,drive_shift", 0);
	priv->sample_delay = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					    "nexell,sample_dly", 0);
	priv->sample_shift = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
					    "nexell,sample_shift", 0);

	if (fdtdec_get_int(gd->fdt_blob, dev->of_offset, "nexell,ddr", 0))
		host->caps |= MMC_MODE_DDR_52MHz;

	return 0;
}

static int nexell_dwmmc_probe(struct udevice *dev)
{
	struct mmc_uclass_priv *upriv = dev_get_uclass_priv(dev);
	struct nexell_dwmmc_priv *priv = dev_get_priv(dev);
	struct dwmci_host *host = &priv->host;
	int fifo_depth;
	u32 freq;
	int ret;

	/* Get max frequency */
	freq = fdtdec_get_int(gd->fdt_blob, dev->of_offset, "frequency",
			      NX_MMC_MIN_CLOCK);

	fifo_depth = fdtdec_get_int(gd->fdt_blob, dev->of_offset,
				    "fifo-depth", 0x20);
	if (fifo_depth < 0)
		return -EINVAL;

	host->fifoth_val = MSIZE(0x2) |
		RX_WMARK(fifo_depth / 2 - 1) | TX_WMARK(fifo_depth / 2);

	dw_mci_set_clk(host->dev_index, freq * 4);

	ret = add_dwmci(host, freq, NX_MMC_MIN_CLOCK);
	if (ret)
		return ret;

#ifdef CONFIG_ARCH_S5P6818
	if (host->buswidth == 8)
		nx_tieoff_set(NX_TIEOFF_MMC_8BIT, 1);
#endif

	dw_mci_reset(host->dev_index);
	dw_mci_clk_delay(priv);

	upriv->mmc = host->mmc;

	return 0;
}

static const struct udevice_id nexell_dwmmc_ids[] = {
	{ .compatible = "nexell,nexell-dwmmc" },
	{ }
};

U_BOOT_DRIVER(nexell_dwmmc_drv) = {
	.name		= "nexell_dwmmc",
	.id		= UCLASS_MMC,
	.of_match	= nexell_dwmmc_ids,
	.ofdata_to_platdata = nexell_dwmmc_ofdata_to_platdata,
	.probe		= nexell_dwmmc_probe,
	.priv_auto_alloc_size = sizeof(struct nexell_dwmmc_priv),
};
