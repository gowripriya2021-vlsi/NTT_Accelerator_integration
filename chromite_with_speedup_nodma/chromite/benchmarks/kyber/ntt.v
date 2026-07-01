module ntt_iterative_optimized (
	clk,
	rst_n,
	start,
	inverse,
	data_in,
	data_out,
	done
);
	parameter integer DATA_WIDTH = 14;
	parameter integer N = 256;
	parameter integer Q = 3329;
	parameter integer ROOT = 17;
	input wire clk;
	input wire rst_n;
	input wire start;
	input wire inverse;
	input wire [(N * DATA_WIDTH) - 1:0] data_in;
	output reg [(N * DATA_WIDTH) - 1:0] data_out;
	output reg done;
	localparam integer LOGN = $clog2(N);
	function automatic [DATA_WIDTH - 1:0] modmul;
		input [DATA_WIDTH - 1:0] a;
		input [DATA_WIDTH - 1:0] b;
		input integer modulus;
		reg [(2 * DATA_WIDTH) - 1:0] product;
		begin
			product = a * b;
			modmul = product % modulus;
		end
	endfunction
	function automatic [DATA_WIDTH - 1:0] modadd;
		input [DATA_WIDTH - 1:0] a;
		input [DATA_WIDTH - 1:0] b;
		input integer modulus;
		reg [DATA_WIDTH:0] sum;
		begin
			sum = a + b;
			if (sum >= modulus)
				sum = sum - modulus;
			modadd = sum;
		end
	endfunction
	function automatic [DATA_WIDTH - 1:0] modsub;
		input [DATA_WIDTH - 1:0] a;
		input [DATA_WIDTH - 1:0] b;
		input integer modulus;
		reg [DATA_WIDTH:0] diff;
		begin
			diff = a - b;
			if (diff[DATA_WIDTH])
				diff = diff + modulus;
			modsub = diff;
		end
	endfunction
	function automatic [LOGN - 1:0] bit_reverse;
		input [LOGN - 1:0] val;
		integer i;
		reg [LOGN - 1:0] result;
		begin
			result = 0;
			for (i = 0; i < LOGN; i = i + 1)
				result = (result << 1) | ((val >> i) & 1);
			bit_reverse = result;
		end
	endfunction
	function automatic integer mod_exp;
		input integer base;
		input integer exp;
		input integer modulus;
		integer result;
		integer b;
		integer e;
		begin
			result = 1;
			b = base % modulus;
			e = exp;
			while (e > 0) begin
				if (e & 1)
					result = (result * b) % modulus;
				b = (b * b) % modulus;
				e = e >> 1;
			end
			mod_exp = result;
		end
	endfunction
	function automatic integer mod_inverse;
		input integer a;
		input integer m;
		integer m0;
		integer x0;
		integer x1;
		integer q;
		integer t;
		integer temp_a;
		integer temp_m;
		begin
			temp_a = a;
			temp_m = m;
			m0 = m;
			x0 = 0;
			x1 = 1;
			if (m == 1)
				mod_inverse = 0;
			else begin
				while (temp_a > 1) begin
					q = temp_a / temp_m;
					t = temp_m;
					temp_m = temp_a % temp_m;
					temp_a = t;
					t = x0;
					x0 = x1 - (q * x0);
					x1 = t;
				end
				if (x1 < 0)
					x1 = x1 + m0;
				mod_inverse = x1;
			end
		end
	endfunction
	integer N_INV;
	integer ROOT_INV;
	reg [DATA_WIDTH - 1:0] twiddle [0:N - 1];
	initial begin : sv2v_autoblock_1
		integer i;
		ROOT_INV = mod_inverse(ROOT, Q);
		N_INV = mod_inverse(N, Q);
		$display("=== NTT Module Initialization ===");	
		$display("N=%0d, Q=%0d, ROOT=%0d, ROOT_INV=%0d, N_INV=%0d", N, Q, ROOT, ROOT_INV, N_INV);
		twiddle[0] = 1;
		for (i = 1; i < N; i = i + 1)
			twiddle[i] = modmul(twiddle[i - 1], ROOT, Q);
		$display("Twiddle[0]=%0d, Twiddle[1]=%0d, Twiddle[2]=%0d", twiddle[0], twiddle[1], twiddle[2]);
		$display("Twiddle factors initialized");
		$display("=================================\n");
	end
	reg [DATA_WIDTH - 1:0] mem [0:N - 1];
	reg [31:0] state;
	reg [LOGN - 1:0] stage;
	reg [LOGN - 1:0] group;
	reg [LOGN - 1:0] butterfly;
	wire stage_done;
	wire all_stages_done;
	assign stage_done = (butterfly == (1 << stage)) && (group == (N >> (stage + 1)));
	assign all_stages_done = stage == LOGN;
	always @(posedge clk or negedge rst_n)
		if (!rst_n) begin
			state = 32'd0;
			done = 0;
			stage = 0;
			group = 0;
			butterfly = 0;
			begin : sv2v_autoblock_2
				integer i;
				for (i = 0; i < N; i = i + 1)
					begin
						mem[i] = 0;
						data_out[((N - 1) - i) * DATA_WIDTH+:DATA_WIDTH] = 0;
					end
			end
		end
		else
			case (state)
				32'd0: begin
					done = 0;
					if (start) begin
						state= 32'd1;
						stage = 0;
						group = 0;
						butterfly = 0;
					end
				end
				32'd1: begin
					begin : sv2v_autoblock_3
						integer i;
						for (i = 0; i < N; i = i + 1)
							mem[i] = data_in[((N - 1) - i) * DATA_WIDTH+:DATA_WIDTH];
					end
					state = 32'd2;
				end
				32'd2:
					if (!all_stages_done) begin : sv2v_autoblock_4
						integer m;
						integer idx1;
						integer idx2;
						integer k;
						integer twiddle_idx;
						reg [DATA_WIDTH - 1:0] u;
						reg [DATA_WIDTH - 1:0] v;
						reg [DATA_WIDTH - 1:0] twiddle_val;
						m = 1 << stage;
						idx1 = ((group * 2) * m) + butterfly;
						idx2 = idx1 + m;
						k = butterfly * (N / (2 * m));
						twiddle_idx = (inverse ? (N - k) % N : k);
						u = mem[idx1];
						v = mem[idx2];
						twiddle_val = twiddle[twiddle_idx];
						if (inverse) begin : sv2v_autoblock_5
							reg [DATA_WIDTH - 1:0] v_twiddled;
							v_twiddled = modmul(v, twiddle_val, Q);
							mem[idx1] = modadd(u, v_twiddled, Q);
							mem[idx2] = modsub(u, v_twiddled, Q);
						end
						else begin : sv2v_autoblock_6
							reg [DATA_WIDTH - 1:0] v_twiddled;
							v_twiddled = modmul(v, twiddle_val, Q);
							mem[idx1] = modadd(u, v_twiddled, Q);
							mem[idx2] = modsub(u, v_twiddled, Q);
						end
						if (butterfly < (m - 1))
							butterfly = butterfly + 1;
						else begin
							butterfly = 0;
							if (group < ((N / (2 * m)) - 1))
								group = group + 1;
							else begin
								group = 0;
								stage = stage + 1;
							end
						end
					end
					else if (inverse)
						state = 32'd3;
					else
						state = 32'd4;
				32'd3: begin
					begin : sv2v_autoblock_7
						integer i;
						for (i = 0; i < N; i = i + 1)
							mem[i] = modmul(mem[i], N_INV, Q);
					end
					state = 32'd4;
				end
				32'd4: begin
					begin : sv2v_autoblock_8
						integer i;
						for (i = 0; i < N; i = i + 1)
							data_out[((N - 1) - i) * DATA_WIDTH+:DATA_WIDTH] = mem[bit_reverse(i)];
					end
					done = 1;
					state = 32'd0;
				end
			endcase
endmodule
