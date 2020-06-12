#include "nvs_flash.h"
#include <glib.h>

static GKeyFile *f;

esp_err_t nvs_flash_init()
{
    GError *error = NULL;
    f = g_key_file_new();

    g_key_file_load_from_file (f,
                               "nvs.txt",
                               G_KEY_FILE_NONE,
                               &error);
    return ESP_OK;
}

esp_err_t nvs_flash_erase()
{
    return ESP_OK;
}

esp_err_t nvs_open(const char* name, nvs_open_mode_t open_mode, nvs_handle_t *out_handle)
{
    return ESP_OK;
}

esp_err_t nvs_get_i32 (nvs_handle_t handle, const char* key, int32_t* out_value)
{
    GError *error;

    gint64 val = g_key_file_get_int64 (f,
                                       "interfacez",
                                       key,
                                       &error);
    if (error==NULL) {
        *out_value = (int32_t)(val&0xffffffff);
        return ESP_OK;
    }

    return ESP_ERR_NOT_FOUND;
}

esp_err_t nvs_get_u32 (nvs_handle_t handle, const char* key, uint32_t* out_value)
{
    GError *error;

    gint64 val = g_key_file_get_int64 (f,
                                       "interfacez",
                                       key,
                                       &error);
    if (error==NULL) {
        *out_value = (uint32_t)(val&0xffffffff);
        return ESP_OK;
    }

    return ESP_ERR_NOT_FOUND;
}

esp_err_t nvs_get_u8 (nvs_handle_t handle, const char* key, uint8_t* out_value)
{
    GError *error;

    gint64 val = g_key_file_get_int64 (f,
                                       "interfacez",
                                       key,
                                       &error);
    if (error==NULL) {
        *out_value = (uint8_t)(val&0xff);
        return ESP_OK;
    }

    return ESP_ERR_NOT_FOUND;
}

esp_err_t nvs_get_str(nvs_handle_t handle, const char* key, char* out_value, size_t* length)
{
    GError *error;

    char *str = g_key_file_get_string (f,
                                       "interfacez",
                                       key,
                                       &error);
    if (error==NULL) {
        unsigned len = strlen(str);
        memcpy(out_value, str, len+1);
        *length = len;
        return ESP_OK;
    }

    return ESP_ERR_NOT_FOUND;
}

void nvs_close(nvs_handle_t handle)
{
}
