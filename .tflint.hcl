# Configuración de tflint para todos los stacks y módulos del repositorio.
# Solo se usa el ruleset "terraform" integrado en tflint, con su preset
# recomendado: no se descargan plugins (sin "source" ni "version").
# Se ejecuta desde la raíz (scripts/check.sh) con ruta absoluta:
#   tflint --recursive --config "$PWD/.tflint.hcl"
# Sin --config, `tflint --recursive` busca la configuración en cada
# subdirectorio y no aplica este archivo a los stacks.

config {
  # Inspecciona también las llamadas a módulos locales (modules/*).
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Requisito 1.5: toda variable declara tipo y descripción. Ya forman parte
# del preset recomendado; se habilitan aquí de forma explícita para que no
# dependan de cambios futuros del preset.
rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}
