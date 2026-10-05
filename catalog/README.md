# Catálogo de parches

`catalog.json` es la lista que la pestaña **Parches** descarga al abrirse.
Cada entrada aparece en la lista con el botón **Descargar parche** hasta que se instala.

```json
{
  "patches": [
    {
      "id": "fps-120",
      "name": "FPS 120",
      "description": "Texto corto que se muestra debajo del nombre.",
      "version": "1.0.0",
      "size": 170000,
      "url": "https://github.com/USUARIO/3105/raw/main/catalog/patches/fps-120.3105"
    }
  ]
}
```

- `id`: identificador único y fijo de la entrada (no lo cambies después de publicarla).
- `name`: debe ser igual al nombre del proyecto del parche, así la app lo detecta como instalado.
- `description`, `version`, `size` (en bytes): opcionales.
- `url`: enlace **HTTPS** directo al archivo `.3105`.
- `packageID`: opcional, UUID del paquete (otra forma de detectar que está instalado).

Los archivos `.3105` se crean en la app (Crear parche → Exportar) y se suben a `catalog/patches/`.
