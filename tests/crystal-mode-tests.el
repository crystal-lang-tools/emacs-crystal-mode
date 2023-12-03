(require 'crystal-mode)

(defun crystal-mode-with-text (text)
  "Apply crystal-mode to TEXT"
  (with-temp-buffer
    (crystal-mode)
    (insert text)
    (indent-region (point-min) (point-max))
    (buffer-substring (point-min) (point-max))))

(ert-deftest crystal-mode-test-abstract-indent ()
  "Commentary::"
  (should (string=
           "
abstract class Demo
  abstract def method1
  abstract def method2
  def method3
    if true
    end
  end
  abstract def method4
  def method5
    if true
    end
  end
end
"
           (crystal-mode-with-text "
abstract class Demo
abstract def method1
abstract def method2
def method3
if true
end
end
abstract def method4
def method5
if true
end
end
end
"))))
