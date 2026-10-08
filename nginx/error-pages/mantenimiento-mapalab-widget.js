(() => {
    const NOMBRE = 'iieg-mapalab';
    if (customElements.get(NOMBRE)) return;

    const ESTILOS = `
        :host {
            display: block;
            width: 100%;
            min-height: 320px;
            position: relative;
            overflow: hidden;
            border-radius: var(--mapalab-radius, 8px);
            box-shadow: var(--mapalab-shadow, 0 1px 3px rgba(0,0,0,0.08));
            font-family: var(--mapalab-font, system-ui, -apple-system, sans-serif);
        }
        .aviso {
            position: absolute;
            inset: 0;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 10px;
            padding: 20px;
            text-align: center;
            background: #F9F6FB;
            color: #374151;
        }
        svg { width: 44px; height: 44px; }
        h3 { margin: 0; font-size: 15px; font-weight: 700; color: #5C2472; }
        p { margin: 0; font-size: 13px; color: #6B7280; max-width: 420px; }
    `;

    const ICONO = `
        <svg viewBox="0 0 48 48" aria-hidden="true">
            <path d="M24 17.5l16 10.5-16 10.5L8 28z" fill="none" stroke="#5C2472" stroke-width="2.5" stroke-linejoin="round"/>
            <path d="M24 7l16 10.5L24 28 8 17.5z" fill="none" stroke="#FF8300" stroke-width="2.5" stroke-linejoin="round"/>
        </svg>
    `;

    const medida = valor => (/^\d+$/.test(valor) ? `${valor}px` : valor);

    class AvisoMantenimiento extends HTMLElement {
        static get observedAttributes() {
            return ['height', 'width'];
        }

        connectedCallback() {
            if (!this.shadowRoot) {
                const raiz = this.attachShadow({ mode: 'open' });
                raiz.innerHTML = `
                    <style>${ESTILOS}</style>
                    <div class="aviso" role="status" aria-live="polite">
                        ${ICONO}
                        <h3>MapaLab se está actualizando</h3>
                        <p>El mapa vuelve en unos minutos.</p>
                    </div>
                `;
            }
            this.aplicarMedidas();
        }

        attributeChangedCallback() {
            this.aplicarMedidas();
        }

        aplicarMedidas() {
            const alto = this.getAttribute('height');
            const ancho = this.getAttribute('width');
            if (alto) this.style.height = medida(alto);
            if (ancho) this.style.width = medida(ancho);
        }
    }

    customElements.define(NOMBRE, AvisoMantenimiento);
    window.iiegMapalab = window.iiegMapalab || {};
    window.iiegMapalab.mantenimiento = true;
})();
