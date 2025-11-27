window.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-include]").forEach(async el => {
        const file = el.getAttribute("data-include"); // misal "sidebar.html"

        try {
            const res = await fetch(file);
            if (!res.ok) throw new Error(res.status);

            const html = await res.text();
            el.innerHTML = html;

            // load semua <script src="..."> di dalam HTML yang di-include
            const scripts = el.querySelectorAll("script[src]");
            scripts.forEach(s => {
                const newScript = document.createElement("script");
                // karena semua js ada di folder yang sama dengan include.js
                // pastikan path relatif benar
                const srcPath = s.getAttribute("src");
                newScript.src = srcPath;
                newScript.defer = true; // optional, biar non-blocking
                document.body.appendChild(newScript);
            });

        } catch (err) {
            el.innerHTML = `<p style="color:red">Gagal memuat ${file}</p>`;
        }
    });
});
