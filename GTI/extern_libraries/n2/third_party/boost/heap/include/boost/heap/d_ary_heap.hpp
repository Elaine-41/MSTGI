// Minimal boost::heap::d_ary_heap wrapper for n2 library
// This is a simplified implementation to avoid downloading full boost

#ifndef BOOST_HEAP_D_ARY_HEAP_HPP
#define BOOST_HEAP_D_ARY_HEAP_HPP

#include <vector>
#include <algorithm>
#include <functional>

namespace boost {
namespace heap {

template<int Arity>
struct arity {
    static const int value = Arity;
};

template<typename Comparer>
struct compare {
    typedef Comparer type;
};

// Extract compare type from template parameters
template<typename T, typename Option1, typename Option2>
struct heap_traits {
    typedef std::less<T> compare_type;
};

template<typename T, typename ArityOpt, typename CompareOpt>
struct heap_traits<T, ArityOpt, compare<CompareOpt>> {
    typedef CompareOpt compare_type;
};

template<typename T, typename Option1 = arity<4>, typename Option2 = compare<std::less<T>>>
class d_ary_heap {
private:
    std::vector<T> data_;
    typedef typename heap_traits<T, Option1, Option2>::compare_type CompareType;
    CompareType compare_;

public:
    d_ary_heap() : compare_(CompareType()) {}
    
    void push(const T& value) {
        data_.push_back(value);
        std::push_heap(data_.begin(), data_.end(), compare_);
    }
    
    template<typename... Args>
    void emplace(Args&&... args) {
        data_.emplace_back(std::forward<Args>(args)...);
        std::push_heap(data_.begin(), data_.end(), compare_);
    }
    
    void pop() {
        std::pop_heap(data_.begin(), data_.end(), compare_);
        data_.pop_back();
    }
    
    const T& top() const {
        return data_.front();
    }
    
    bool empty() const {
        return data_.empty();
    }
    
    size_t size() const {
        return data_.size();
    }
    
    void clear() {
        data_.clear();
    }
};

} // namespace heap
} // namespace boost

#endif // BOOST_HEAP_D_ARY_HEAP_HPP
