import matplotlib
matplotlib.use("Agg")   # Backend no interactivo: guarda PNG sin abrir ventana
"""
calc_coefficients.py
====================
Calcula los coeficientes de los 8 filtros IIR biquad pasa-banda para el
ecualizador grafico de 8 bandas implementado en FPGA (DE2-115).

Metodo: Audio-EQ Cookbook (Robert Bristow-Johnson) via scipy.signal.iirpeak
Parametros:
  - Fs      = 48000 Hz  (frecuencia de muestreo del codec WM8731)
  - Q       = 0.707     (Butterworth, cruce suave entre bandas)
  - Formato = Q2.14 signed 16-bit  (FRAC_BITS = 14, escala = 2^14 = 16384)
  - Bandas  = 63, 125, 250, 500, 1000, 2000, 4000, 8000 Hz

Salidas:
  - scripts/coeficientes_calculados.txt  : tabla legible con todos los valores
  - scripts/coeff_rom_values.vhd         : fragmento VHDL listo para copiar a coeff_rom.vhd
  - scripts/respuesta_frecuencia.png     : grafica de respuesta en frecuencia

Uso:
  python scripts/calc_coefficients.py
"""

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from scipy.signal import iirpeak, freqz
import os

# =============================================================================
# PARAMETROS DEL PROYECTO
# =============================================================================
FS          = 48_000          # Frecuencia de muestreo (Hz)
Q           = 0.707           # Factor Q Butterworth (cruce suave entre bandas)
FRAC_BITS   = 14              # Bits fraccionarios del formato Q2.14
SCALE       = 2 ** FRAC_BITS  # = 16384  (1.0 en Q2.14)
MAX_COEFF   = 32767           # Maximo valor signed 16-bit
MIN_COEFF   = -32768          # Minimo valor signed 16-bit

# Frecuencias centrales de las 8 bandas (Hz) - octavas estandar
BAND_FREQS = [63, 125, 250, 500, 1000, 2000, 4000, 8000]
NUM_BANDS  = len(BAND_FREQS)


# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

def float_to_q214(value: float) -> int:
    """
    Convierte un coeficiente float a formato Q2.14 (signed 16-bit).
    - Escala por 2^14 = 16384
    - Redondea al entero mas cercano
    - Satura al rango [-32768, +32767]
    - Verifica que el valor original este en el rango representable [-2.0, +1.99994]
    """
    if abs(value) > 2.0:
        print(f"  [ADVERTENCIA] Coeficiente {value:.6f} fuera del rango Q2.14 [-2, +2) -> saturando")

    scaled = value * SCALE
    rounded = int(round(scaled))
    # Saturacion
    if rounded > MAX_COEFF:
        print(f"  [SATURACION] {value:.6f} -> {rounded} > {MAX_COEFF}, saturando a {MAX_COEFF}")
        return MAX_COEFF
    if rounded < MIN_COEFF:
        print(f"  [SATURACION] {value:.6f} -> {rounded} < {MIN_COEFF}, saturando a {MIN_COEFF}")
        return MIN_COEFF
    return rounded


def q214_to_float(q_val: int) -> float:
    """Convierte un valor Q2.14 de vuelta a float (para verificacion)."""
    return q_val / SCALE


def check_stability(b: np.ndarray, a: np.ndarray) -> bool:
    """
    Verifica que todos los polos del filtro esten dentro del circulo unitario.
    Si algun polo tiene |polo| >= 1, el filtro es inestable.
    """
    # Los polos son las raices del denominador
    poles = np.roots(a)
    stable = all(abs(p) < 1.0 for p in poles)
    return stable, poles


def compute_quantized_response(b_q: list, a_q: list, worN: int = 4096) -> tuple:
    """
    Calcula la respuesta en frecuencia de los coeficientes cuantizados a Q2.14.
    Convierte de vuelta a float para usar freqz.
    """
    b_float = [q214_to_float(v) for v in b_q]
    a_float = [q214_to_float(v) for v in a_q]
    # Normalizar: a[0] debe ser 1.0 en la forma estandar
    # En nuestro formato ya estan normalizados (el Audio-EQ Cookbook divide por a0)
    w, H = freqz(b_float, a_float, worN=worN)
    freqs = w * FS / (2 * np.pi)
    return freqs, np.abs(H)


# =============================================================================
# CALCULO DE COEFICIENTES
# =============================================================================

print("=" * 70)
print("CALCULADOR DE COEFICIENTES IIR BIQUAD PASA-BANDA")
print(f"  Fs = {FS} Hz   |   Q = {Q}   |   Formato = Q2.14 (signed 16-bit)")
print("=" * 70)

results = []  # Lista de dicts con todos los datos de cada banda

for i, f0 in enumerate(BAND_FREQS):
    print(f"\nBanda {i} | f0 = {f0:5d} Hz")
    print("-" * 40)

    # ------------------------------------------------------------------
    # 1. Calcular coeficientes float con scipy.signal.iirpeak
    #    iirpeak(w0, Q) donde w0 es frecuencia normalizada en [0, 1]
    #    w0 = f0 / (Fs/2)  = f0 * 2 / Fs
    # ------------------------------------------------------------------
    w0_norm = f0 / (FS / 2.0)  # Normalizado a [0, 1] (1 = Nyquist)
    b_float, a_float = iirpeak(w0_norm, Q)

    # iirpeak devuelve:
    #   b = [b0, b1, b2]   con b0=k, b1=0, b2=-k  (donde k = (1-cos(w0))/2)
    #   a = [1,  a1, a2]   con a1=-2cos(w0), a2=(1-k/(Q*sin(w0)))
    # El coeficiente a[0] ya es 1.0 (normalizado)

    b0_f, b1_f, b2_f = b_float[0], b_float[1], b_float[2]
    a0_f, a1_f, a2_f = a_float[0], a_float[1], a_float[2]

    print(f"  Coeficientes float (normalizados, a0=1):")
    print(f"    b0 = {b0_f:+.8f}")
    print(f"    b1 = {b1_f:+.8f}")
    print(f"    b2 = {b2_f:+.8f}")
    print(f"    a1 = {a1_f:+.8f}  (a0 = {a0_f:.6f} -> ya es 1.0)")
    print(f"    a2 = {a2_f:+.8f}")

    # ------------------------------------------------------------------
    # 2. Verificar estabilidad del filtro float
    # ------------------------------------------------------------------
    stable, poles = check_stability(b_float, a_float)
    print(f"  Estabilidad (float): {'OK - todos los polos dentro del circulo unitario' if stable else 'INESTABLE!'}")
    for pi_, p in enumerate(poles):
        print(f"    polo[{pi_}] = {p:.6f}  |  |polo| = {abs(p):.6f}")

    # ------------------------------------------------------------------
    # 3. Convertir a Q2.14
    # ------------------------------------------------------------------
    b0_q = float_to_q214(b0_f)
    b1_q = float_to_q214(b1_f)
    b2_q = float_to_q214(b2_f)
    a1_q = float_to_q214(a1_f)
    a2_q = float_to_q214(a2_f)

    print(f"  Coeficientes Q2.14 (signed 16-bit, escala x{SCALE}):")
    print(f"    b0 = {b0_q:6d}   ({q214_to_float(b0_q):+.8f} float)")
    print(f"    b1 = {b1_q:6d}   ({q214_to_float(b1_q):+.8f} float)")
    print(f"    b2 = {b2_q:6d}   ({q214_to_float(b2_q):+.8f} float)")
    print(f"    a1 = {a1_q:6d}   ({q214_to_float(a1_q):+.8f} float)")
    print(f"    a2 = {a2_q:6d}   ({q214_to_float(a2_q):+.8f} float)")

    # ------------------------------------------------------------------
    # 4. Verificar estabilidad del filtro cuantizado
    # ------------------------------------------------------------------
    a_q_float = [1.0, q214_to_float(a1_q), q214_to_float(a2_q)]
    b_q_float = [q214_to_float(b0_q), q214_to_float(b1_q), q214_to_float(b2_q)]
    stable_q, poles_q = check_stability(b_q_float, a_q_float)
    print(f"  Estabilidad (Q2.14): {'OK' if stable_q else 'INESTABLE - REVISAR!'}")
    if not stable_q:
        for pi_, p in enumerate(poles_q):
            print(f"    polo[{pi_}] = {p:.6f}  |  |polo| = {abs(p):.6f}")

    # ------------------------------------------------------------------
    # 5. Error de cuantizacion
    # ------------------------------------------------------------------
    err_b0 = abs(b0_f - q214_to_float(b0_q))
    err_a1 = abs(a1_f - q214_to_float(a1_q))
    err_a2 = abs(a2_f - q214_to_float(a2_q))
    print(f"  Error de cuantizacion max: {max(err_b0, err_a1, err_a2):.2e}")

    results.append({
        "band": i,
        "f0": f0,
        "b0_f": b0_f, "b1_f": b1_f, "b2_f": b2_f,
        "a1_f": a1_f, "a2_f": a2_f,
        "b0_q": b0_q, "b1_q": b1_q, "b2_q": b2_q,
        "a1_q": a1_q, "a2_q": a2_q,
        "stable_float": stable, "stable_q": stable_q,
        "b_float": b_float, "a_float": a_float,
        "b_q_float": b_q_float, "a_q_float": a_q_float,
    })

# =============================================================================
# GUARDAR: coeficientes_calculados.txt
# =============================================================================

os.makedirs("scripts", exist_ok=True)
output_txt = "scripts/coeficientes_calculados.txt"

with open(output_txt, "w", encoding="utf-8") as f:
    f.write("=" * 72 + "\n")
    f.write("COEFICIENTES IIR BIQUAD PASA-BANDA - ECUALIZADOR GRAFICO FPGA\n")
    f.write(f"Fs = {FS} Hz  |  Q = {Q}  |  Formato Q2.14 (escala = {SCALE})\n")
    f.write(f"Bandas: {BAND_FREQS} Hz\n")
    f.write("=" * 72 + "\n\n")

    f.write(f"{'Banda':>5} | {'f0(Hz)':>7} | {'b0':>7} | {'b1':>7} | {'b2':>7} | {'a1':>7} | {'a2':>7} | {'Estable':>8}\n")
    f.write("-" * 72 + "\n")
    for r in results:
        stable_str = "SI" if r["stable_q"] else "NO !!!"
        f.write(
            f"  {r['band']:3d}  | {r['f0']:7d} | "
            f"{r['b0_q']:7d} | {r['b1_q']:7d} | {r['b2_q']:7d} | "
            f"{r['a1_q']:7d} | {r['a2_q']:7d} | {stable_str:>8}\n"
        )

    f.write("\n\n")
    f.write("DETALLE POR BANDA (float y Q2.14):\n")
    f.write("-" * 72 + "\n")
    for r in results:
        f.write(f"\nBanda {r['band']} | f0 = {r['f0']} Hz\n")
        f.write(f"  Float:  b0={r['b0_f']:+.8f}  b1={r['b1_f']:+.8f}  b2={r['b2_f']:+.8f}\n")
        f.write(f"          a1={r['a1_f']:+.8f}  a2={r['a2_f']:+.8f}\n")
        f.write(f"  Q2.14:  b0={r['b0_q']:7d}     b1={r['b1_q']:7d}     b2={r['b2_q']:7d}\n")
        f.write(f"          a1={r['a1_q']:7d}     a2={r['a2_q']:7d}\n")
        f.write(f"  Estabilidad float: {'OK' if r['stable_float'] else 'INESTABLE'} | "
                f"Q2.14: {'OK' if r['stable_q'] else 'INESTABLE'}\n")

print(f"\n[OK] Tabla de coeficientes guardada en: {output_txt}")

# =============================================================================
# GUARDAR: coeff_rom_values.vhd  (fragmento VHDL listo para pegar)
# =============================================================================

output_vhd = "scripts/coeff_rom_values.vhd"

with open(output_vhd, "w", encoding="utf-8") as f:
    f.write("-- =============================================================================\n")
    f.write("-- FRAGMENTO PARA REEMPLAZAR EN: src/coeff_rom.vhd\n")
    f.write("-- Sustituir el bloque 'constant COEFF_TABLE' con el siguiente contenido.\n")
    f.write("--\n")
    f.write(f"-- Generado por: scripts/calc_coefficients.py\n")
    f.write(f"-- Fs = {FS} Hz  |  Q = {Q}  |  Formato Q2.14 (escala = {SCALE})\n")
    f.write(f"-- Bandas (Hz): {BAND_FREQS}\n")
    f.write("-- =============================================================================\n\n")
    f.write("    constant COEFF_TABLE : coeff_array_t := (\n")

    for idx, r in enumerate(results):
        comma = "" if idx == NUM_BANDS - 1 else ","
        f.write(f"        -- Banda {r['band']}: {r['f0']:5d} Hz  "
                f"(b0={r['b0_q']:7d}, b1={r['b1_q']:7d}, b2={r['b2_q']:7d}, "
                f"a1={r['a1_q']:7d}, a2={r['a2_q']:7d})  "
                f"{'[ESTABLE]' if r['stable_q'] else '[INESTABLE!]'}\n")
        f.write(f"        (c_b0 => to_signed({r['b0_q']:7d}, 16),\n")
        f.write(f"         c_b1 => to_signed({r['b1_q']:7d}, 16),\n")
        f.write(f"         c_b2 => to_signed({r['b2_q']:7d}, 16),\n")
        f.write(f"         c_a1 => to_signed({r['a1_q']:7d}, 16),\n")
        f.write(f"         c_a2 => to_signed({r['a2_q']:7d}, 16)){comma}\n\n")

    f.write("    );\n")

print(f"[OK] Fragmento VHDL listo guardado en: {output_vhd}")

# =============================================================================
# GRAFICAS
# =============================================================================

worN = 8192
fig, axes = plt.subplots(2, 1, figsize=(14, 9))
fig.suptitle(
    f"Respuesta en Frecuencia — 8 Filtros IIR Biquad Pasa-Banda\n"
    f"Fs={FS} Hz  |  Q={Q} (Butterworth)  |  Formato Q2.14",
    fontsize=13, fontweight="bold"
)

colors = plt.cm.tab10(np.linspace(0, 1, NUM_BANDS))

ax1, ax2 = axes[0], axes[1]

# Acumulador para la respuesta combinada (suma de las 8 bandas con ganancia unitaria)
# Se calcula con los coeficientes cuantizados
H_combined_q = np.zeros(worN, dtype=complex)

for r in results:
    freqs_f, mag_f = compute_quantized_response(
        [r["b0_q"], r["b1_q"], r["b2_q"]],
        [SCALE, r["a1_q"], r["a2_q"]],  # a[0] = SCALE porque a0_float=1.0 -> Q2.14=16384
        worN=worN
    )

    # Para la suma compleja (respuesta combinada)
    w_norm = np.linspace(0, np.pi, worN)
    _, H_complex = freqz(
        [q214_to_float(r["b0_q"]), q214_to_float(r["b1_q"]), q214_to_float(r["b2_q"])],
        [1.0, q214_to_float(r["a1_q"]), q214_to_float(r["a2_q"])],
        worN=worN
    )
    H_combined_q += H_complex

    color = colors[r["band"]]
    label = f"{r['f0']} Hz"

    # Grafica 1: respuestas individuales
    mask = freqs_f <= FS / 2
    ax1.semilogx(freqs_f[mask], 20 * np.log10(np.abs(H_complex[mask]) + 1e-12),
                 color=color, linewidth=1.5, label=label)

    # Marcar frecuencia central
    ax1.axvline(r["f0"], color=color, linestyle=":", alpha=0.4, linewidth=0.8)

# Grafica 2: respuesta combinada
freqs_ax = np.linspace(0, FS / 2, worN)
mask2 = freqs_ax >= 10
ax2.semilogx(freqs_ax[mask2],
             20 * np.log10(np.abs(H_combined_q[mask2]) + 1e-12),
             color="royalblue", linewidth=2.0, label="Suma de 8 bandas (ganancias iguales)")

# Referencia 0 dB
for ax in [ax1, ax2]:
    ax.axhline(0, color="gray", linestyle="--", linewidth=0.8, alpha=0.6)
    ax.set_xlim([20, 24000])
    ax.set_ylim([-60, 10])
    ax.set_xlabel("Frecuencia (Hz)", fontsize=10)
    ax.set_ylabel("Magnitud (dB)", fontsize=10)
    ax.grid(True, which="both", alpha=0.3)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(
        lambda x, _: f"{int(x/1000)}k" if x >= 1000 else f"{int(x)}"
    ))
    ax.xaxis.set_major_locator(mticker.LogLocator(
        base=10, subs=[1, 2, 5], numticks=20
    ))

ax1.set_title("Respuestas individuales de las 8 bandas (coeficientes Q2.14)", fontsize=11)
ax1.legend(loc="upper right", fontsize=8, ncol=2, framealpha=0.8)

ax2.set_title("Respuesta combinada: suma de los 8 filtros con ganancia unitaria", fontsize=11)
ax2.legend(loc="upper right", fontsize=9)

# Marcar frecuencias centrales en ax2
for r in results:
    ax2.axvline(r["f0"], color=colors[r["band"]], linestyle=":", alpha=0.4, linewidth=0.8)
    ax2.text(r["f0"], -55, f"{r['f0']}Hz", fontsize=6.5, ha="center",
             color=colors[r["band"]], rotation=90)

plt.tight_layout()

plot_path = "scripts/respuesta_frecuencia.png"
plt.savefig(plot_path, dpi=150, bbox_inches="tight")
print(f"[OK] Grafica guardada en: {plot_path}")

# plt.show() deshabilitado - usar backend Agg (no interactivo)

# =============================================================================
# RESUMEN FINAL
# =============================================================================
print("\n" + "=" * 70)
print("RESUMEN FINAL")
print("=" * 70)
all_stable = all(r["stable_q"] for r in results)
print(f"  Todos los filtros estables (Q2.14): {'SI ✓' if all_stable else 'NO - REVISAR!'}")
print(f"\n  Archivos generados:")
print(f"    {output_txt}")
print(f"    {output_vhd}")
print(f"    {plot_path}")
print(f"\n  Para aplicar los coeficientes al VHDL:")
print(f"    1. Abrir scripts/coeff_rom_values.vhd")
print(f"    2. Copiar el bloque 'constant COEFF_TABLE' en src/coeff_rom.vhd")
print(f"    3. O esperar la Fase 3 (el asistente lo hara automaticamente)")
print("=" * 70)
