import math

N_POINTS = 1024
HALF_N = N_POINTS // 2 
Q_FORMAT = 15
MAX_VAL = (1 << Q_FORMAT) - 1

def create_mif(filename, data_list):
    with open(filename, "w") as f:
        f.write(f"DEPTH = {HALF_N};\n")
        f.write("WIDTH = 16;\n")
        f.write("ADDRESS_RADIX = DEC;\n")
        f.write("DATA_RADIX = BIN;\n") # Pakai Biner agar aman untuk angka negatif
        f.write("CONTENT BEGIN\n")
        
        for addr, val in enumerate(data_list):
            # Konversi angka ke biner 16-bit 2's complement
            bin_str = f"{val & 0xFFFF:016b}"
            f.write(f"{addr} : {bin_str};\n")
            
        f.write("END;\n")

def main():
    twiddle_re_list = []
    twiddle_im_list = []
    
    for k in range(HALF_N):
        # W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N)
        angle = -2.0 * math.pi * k / N_POINTS
        
        real_val = int(round(math.cos(angle) * MAX_VAL))
        imag_val = int(round(math.sin(angle) * MAX_VAL))
        
        twiddle_re_list.append(real_val)
        twiddle_im_list.append(imag_val)
        
    create_mif("twiddle_re.mif", twiddle_re_list)
    create_mif("twiddle_im.mif", twiddle_im_list)
    print("Sukses! File twiddle_re.mif dan twiddle_im.mif berhasil dibuat.")

if __name__ == "__main__":
    main()