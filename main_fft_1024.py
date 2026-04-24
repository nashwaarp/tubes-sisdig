import serial
import time
import numpy as np
import matplotlib.pyplot as plt
import librosa

# ==========================================
# KONFIGURASI (Sinkron dengan VHDL)
# ==========================================
PORT_COM   = 'COM9'
BAUD_RATE  = 921600    # Baud rate cepat sesuai uart_rx.vhd
N_POINTS   = 1024      # Resolusi FFT
FS         = 44100     # Sampling rate audio 44.1 kHz
AUDIO_FILE = "gitar_chord_G.wav" # Ganti dengan file rekamanku

def main():
    # 1. BACA & PRE-PROCESSING AUDIO
    print("Memproses audio...")
    # Load audio, otomatis di-resample ke FS (44100) dan diubah ke Mono
    y, sr = librosa.load(AUDIO_FILE, sr=FS, mono=True)

    # Ambil 1024 sampel di tengah rekaman agar aman dari silence/hening
    offset = len(y) // 2
    y_1024 = y[offset : offset + N_POINTS]

    # Normalisasi amplitudo
    y_norm = y_1024 / np.max(np.abs(y_1024))
    
    # Konversi ke 8-bit signed integer (-128 to 127) 
    # Di VHDL: ram_wdata_re <= resize(signed(fifo_data), 16)
    y_8bit = (y_norm * 127).astype(np.int8)

    # 2. KOMUNIKASI UART KE FPGA
    print(f"Membuka port {PORT_COM} pada {BAUD_RATE} bps...")
    try:
        ser = serial.Serial(PORT_COM, BAUD_RATE, timeout=3)
        time.sleep(2) # Kasih jeda 2 detik agar koneksi UART stabil
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        print("Mengirim 1024 sampel data ke FPGA...")
        # Konversi array numpy int8 ke format raw bytes untuk dikirim via Serial
        tx_bytes = [int(b) & 0xFF for b in y_8bit]
        ser.write(bytes(tx_bytes))

        # 3. TERIMA HASIL DARI FPGA
        print("Menunggu FSM FPGA menghitung dan mengirim balasan...")
        hasil_raw = bytearray()
        start_wait = time.time()

        # Tunggu sampai FSM SEND_DATA selesai mengirim 1024 bytes (atau timeout 5 detik)
        while len(hasil_raw) < N_POINTS and (time.time() - start_wait) < 5:
            if ser.in_waiting > 0:
                hasil_raw.extend(ser.read(ser.in_waiting))

        ser.close()

        # 4. VISUALISASI SPEKTRUM
        if len(hasil_raw) == N_POINTS:
            print("1024 data magnitudo sukses diterima! Membuat grafik...")

            # Menurut teorema Nyquist, kita hanya pakai setengah spektrum (512 titik)
            spectrum = np.array(list(hasil_raw))[:N_POINTS//2]
            freq_bins = np.arange(N_POINTS//2) * (FS / N_POINTS)

            plt.figure(figsize=(12, 6))
            plt.bar(freq_bins, spectrum, width=(FS/N_POINTS)*0.8, color='skyblue', edgecolor='black')
            
            plt.title(f"FPGA 1024-Point FFT | Sampling Rate: {FS}Hz")
            plt.xlabel("Frekuensi (Hz)")
            plt.ylabel("Magnitudo (Skala 0-255)")
            
            # Kita batasi sumbu X sampai 2000 Hz saja karena nada fundamental gitar 
            # (bahkan senar paling tinggi) berada di bawah 1500 Hz.
            plt.xlim(0, 2000) 
            plt.grid(True, alpha=0.3)
            
            # Deteksi 3 puncak tertinggi
            top_3_indices = np.argsort(spectrum)[-3:]
            for idx in top_3_indices:
                if spectrum[idx] > 10: # Threshold noise
                    plt.text(freq_bins[idx], spectrum[idx]+5, f"{freq_bins[idx]:.1f} Hz", 
                             color='red', fontweight='bold', ha='center')

            plt.tight_layout()
            plt.show()
        else:
            print(f"Error Timeout: Hanya menerima {len(hasil_raw)} dari 1024 byte. Cek FSM atau kabel RX/TX.")

    except Exception as e:
        print(f"Terjadi kesalahan serial: {e}")

if __name__ == '__main__':
    main()