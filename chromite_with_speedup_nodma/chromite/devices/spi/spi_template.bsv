// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// See LICENSE.incore for More details
/*--------------------------------------------------------------------------------------------------
    Author: Babu P S
    Email id: info@incoresemi.com
--------------------------------------------------------------------------------------------------*/
package spi_template;

`include "spi.defines"
import spi :: *;

    (*synthesize*)
    module mkinst_spi_axi4l(Ifc_spi_axi4l#(`PDATASIZE, `PADDR, 0, `SLAVES_SERVED, `TXFIFO_DEPTH));
        let clk   <- exposeCurrentClock;
        let reset <- exposeCurrentReset;
        let ifc();
        mkspi_axi4l#(`SPI_BASE_ADDR, clk, reset) _temp(ifc);
        return ifc;
    endmodule:mkinst_spi_axi4l

    (*synthesize*)
    module mkinst_spi_apb(Ifc_spi_apb#(`PDATASIZE, `PADDR, 0,`SLAVES_SERVED, `TXFIFO_DEPTH));
        let clk <-exposeCurrentClock;
        let reset <-exposeCurrentReset;
        let ifc();
        mkspi_apb#(`SPI_BASE_ADDR, clk, reset) _temp(ifc);
        return ifc;
    endmodule:mkinst_spi_apb

endpackage

