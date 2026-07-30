// MiSTer arcade DIP transfer receiver.
//
// Main_MiSTer's arcade loader always sends the complete 64-bit dip_cur value
// at ioctl index 254, even when an MRA defines fewer than eight bytes.  This
// board has three physical DIP banks.  Do not decode only ioctl_addr[1:0]:
// addresses 4, 5, and 6 would alias banks 1, 2, and 3 and overwrite them with
// the unused high bytes of dip_cur.
module gladiator_dip_loader (
    input  logic        clk,
    input  logic        ioctl_wr,
    input  logic [15:0] ioctl_index,
    input  logic [26:0] ioctl_addr,
    input  logic [7:0]  ioctl_data,
    output logic [7:0]  dsw1 = 8'h5a,
    output logic [7:0]  dsw2 = 8'hbf,
    output logic [7:0]  dsw3 = 8'hff
);

    always_ff @(posedge clk) begin
        if (ioctl_wr && (ioctl_index == 16'd254) &&
                !ioctl_addr[26:2]) begin
            case (ioctl_addr[1:0])
                2'd0: dsw1 <= ioctl_data;
                2'd1: dsw2 <= ioctl_data;
                2'd2: dsw3 <= ioctl_data;
                default: ;
            endcase
        end
    end

endmodule
