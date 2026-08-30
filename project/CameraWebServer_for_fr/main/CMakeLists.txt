idf_component_register(
    SRCS
        "main.cpp"
        "camera_base.cpp"
        "app_httpd.cpp"
        "student.cpp"
        "student_support.cpp"
    INCLUDE_DIRS "."
    REQUIRES
        arduino-esp32
        esp32-camera
        esp_http_server
        esp_timer
        esp_wifi
        spiffs
)
