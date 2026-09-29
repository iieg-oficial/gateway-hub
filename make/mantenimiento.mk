.PHONY: mantenimiento

##@ Operacion

mantenimiento: ## Encender o apagar el aviso de actualizacion de un servicio, con selector
	@$(LIB)
	banner 'MANTENIMIENTO'
	ensure_mantenimiento
	for s in $$MANTENIMIENTO_SERVICIOS; do
		row "$$s" "$$(estado_mantenimiento "$$s")" "$$C_DIM"
	done
	rule
	svc=$$(pick 'Servicio' $$MANTENIMIENTO_SERVICIOS)
	if [ "$$(estado_mantenimiento "$$svc")" = 'encendido' ]; then
		accion=$$(pick 'Accion' 'apagar' 'dejarlo encendido')
	else
		accion=$$(pick 'Accion' 'encender' 'dejarlo apagado')
	fi
	case "$$accion" in
		encender) touch "$$MANTENIMIENTO_DIR/$$svc" ;;
		apagar) rm -f "$$MANTENIMIENTO_DIR/$$svc" ;;
	esac
	rule
	row "$$svc" "$$(estado_mantenimiento "$$svc")" "$$C_GREEN" 'sin recargar nginx'
	printf '\n'
