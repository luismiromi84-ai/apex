create or replace PACKAGE BODY pkg_empresa_logo AS

    -- ---------------------------------------------------------------------
    -- Alta / reemplazo del logo
    -- ---------------------------------------------------------------------
    PROCEDURE prc_guardar_logo (
        p_id_empresa IN NUMBER,
        p_imagen     IN BLOB,
        p_nombre     IN VARCHAR2,
        p_mime       IN VARCHAR2,
        p_usuario    IN VARCHAR2 DEFAULT NULL
    ) IS
        v_tamano number;
        v_mime   varchar2(100);
        v_n      number;
    begin
        if p_id_empresa is null then
            raise_application_error(-20050, 'Falta la empresa del logo.');
        end if;

        if p_imagen is null or dbms_lob.getlength(p_imagen) = 0 then
            raise_application_error(-20051, 'El archivo del logo esta vacio.');
        end if;

        v_tamano := dbms_lob.getlength(p_imagen);
        if v_tamano > c_max_bytes then
            raise_application_error(-20052,
                'El logo no puede pasar de 2 MB. Este pesa ' || round(v_tamano / 1024) || ' KB.');
        end if;

        v_mime := lower(nvl(p_mime, 'image/png'));
        if v_mime not in ('image/png', 'image/jpeg') then
            raise_application_error(-20053,
                'Formato no admitido (' || v_mime || '). Usa PNG o JPG.');
        end if;

        select count(*) into v_n from empresas where id_empresa = p_id_empresa;
        if v_n = 0 then
            raise_application_error(-20054, 'La empresa no existe.');
        end if;

        merge into empresa_logo l
        using (select p_id_empresa as id_empresa from dual) s
           on (l.id_empresa = s.id_empresa)
         when matched then
              update set nombre_archivo = p_nombre,
                         mime_type      = v_mime,
                         tamano         = v_tamano,
                         imagen         = p_imagen,
                         fecha_carga    = sysdate,
                         subido_por     = p_usuario
         when not matched then
              insert (id_empresa, nombre_archivo, mime_type, tamano, imagen,
                      fecha_carga, subido_por)
              values (p_id_empresa, p_nombre, v_mime, v_tamano, p_imagen,
                      sysdate, p_usuario);

        -- EMPRESAS.LOGO_FILENAME deja de estar muerto: guarda el nombre del archivo.
        update empresas set
               logo_filename = p_nombre
         where id_empresa = p_id_empresa;
    end prc_guardar_logo;

    -- ---------------------------------------------------------------------
    -- Baja
    -- ---------------------------------------------------------------------
    PROCEDURE prc_eliminar_logo (p_id_empresa IN NUMBER) IS
    begin
        delete from empresa_logo where id_empresa = p_id_empresa;

        update empresas set
               logo_filename = null
         where id_empresa = p_id_empresa;
    end prc_eliminar_logo;

    -- ---------------------------------------------------------------------
    -- Etiqueta <img> con el logo incrustado
    -- ---------------------------------------------------------------------
    FUNCTION fn_logo_img (
        p_id_empresa IN NUMBER,
        p_estilo     IN VARCHAR2 DEFAULT NULL
    ) RETURN CLOB IS
        v_mime  varchar2(100);
        v_b64   clob;
        v_html  clob;
    begin
        if p_id_empresa is null then
            return null;
        end if;

        select mime_type, apex_web_service.blob2clobbase64(imagen)
          into v_mime, v_b64
          from empresa_logo
         where id_empresa = p_id_empresa;

        v_html := '<img src="data:' || v_mime || ';base64,' || v_b64 || '"'
               || case when p_estilo is not null then ' style="' || p_estilo || '"' end
               || ' alt="Logo de la empresa">';

        return v_html;
    exception
        when no_data_found then
            return null;
    end fn_logo_img;

END pkg_empresa_logo;
/
