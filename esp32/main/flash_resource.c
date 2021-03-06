#include "esp_partition.h"
#include "esp_spi_flash.h"
#include "esp_log.h"
#include "defs.h"
#include "resource.h"
#include "flash_resource.h"
#include "esp_spiffs.h"
#include "fpga.h"

void flash_resource__init(void)
{
#ifndef __linux__
    esp_vfs_spiffs_conf_t conf = {
      .base_path = "/spiffs",
      .partition_label = "resources",
      .max_files = 128,
      .format_if_mount_failed = false
    };
    
    esp_err_t ret = esp_vfs_spiffs_register(&conf);

    if (ret != ESP_OK) {
        if (ret == ESP_FAIL) {
            ESP_LOGE(TAG, "Failed to mount or format filesystem");
        } else if (ret == ESP_ERR_NOT_FOUND) {
            ESP_LOGE(TAG, "Failed to find SPIFFS partition");
        } else {
            ESP_LOGE(TAG, "Failed to initialize SPIFFS (%s)", esp_err_to_name(ret));
        }
        return;
    }
#endif
}
#if 0
uint8_t flash_resource__type(struct resource *r)
{
    struct flash_resource *fr = (struct flash_resource*)r;
    return fr->data->type;
}

uint16_t flash_resource__len(struct resource *r)
{
    struct flash_resource *fr = (struct flash_resource*)r;
    ESP_LOGI(TAG,"Flash resource size: %d", fr->data->len);
    return fr->data->len;
}

int flash_resource__sendToFifo(struct resource *r)
{
    struct flash_resource *fr = (struct flash_resource*)r;
    return fpga__load_resource_fifo( fr->data->data, fr->data->len, RESOURCE_DEFAULT_TIMEOUT);
}

static struct flash_resource flashresource = {
    .r = {
        .type = &flash_resource__type,
        .len = &flash_resource__len,
        .sendToFifo = &flash_resource__sendToFifo,
        .update = NULL,
    },
    .data = NULL
};

struct flash_resource *flash_resource__find(uint8_t id)
{
    const struct flashresourcedata *data = flashresourcedata__finddata(id);
    if (data==NULL) {
        return NULL;
    }
    flashresource.data = data;
    return &flashresource;
}
#endif
