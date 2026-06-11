// Minimal spdlog wrapper for n2 library
#pragma once

#include <memory>
#include <iostream>

namespace spdlog {

class logger {
public:
    template<typename... Args>
    void info(const char* fmt, Args... args) {
        (void)fmt;
        (void)(sizeof...(args));
    }
    
    template<typename... Args>
    void debug(const char* fmt, Args... args) {
        (void)fmt;
        (void)(sizeof...(args));
    }
    
    template<typename... Args>
    void warn(const char* fmt, Args... args) {
        (void)fmt;
        (void)(sizeof...(args));
    }
    
    template<typename... Args>
    void error(const char* fmt, Args... args) {
        (void)fmt;
        (void)(sizeof...(args));
    }
};

inline std::shared_ptr<logger> get(const std::string& name) {
    static std::shared_ptr<logger> instance = std::make_shared<logger>();
    (void)name;
    return instance;
}

inline std::shared_ptr<logger> stdout_logger_mt(const std::string& name) {
    static std::shared_ptr<logger> instance = std::make_shared<logger>();
    (void)name;
    return instance;
}

} // namespace spdlog
