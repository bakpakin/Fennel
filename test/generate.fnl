;; A general-purpose function for generating random values.

(local random-char
       (fn []
         (if (> (math.random) 0.9) ; digits
             (string.char (+ 47 (math.random 10)))
             (> (math.random) 0.5) ; lower case
             (string.char (+ 96 (math.random 26)))
             (> (math.random) 0.5) ; upper case
             (string.char (+ 64 (math.random 26)))
             (> (math.random) 0.5) ; space and punctuation
             (string.char (+ 31 (math.random 16)))
             (> (math.random) 0.5) ; newlines and tabs
             (string.char (+ 9 (math.random 4)))
             :else ; bonus punctuation
             (string.char (+ 58 (math.random 5))))))

(local generators {:number (fn [] ; weighted towards mid-range integers
                             (if (> (math.random) 0.9)
                                 (let [x (math.random 2147483647)]
                                   (math.floor (- x (/ x 2))))
                                 (> (math.random) 0.2)
                                 (math.floor (math.random 2048))
                                 :else (math.random)))
                   :string (fn []
                             (var s "")
                             (for [_ 1 (math.random 16)]
                               (set s (.. s (random-char))))
                             s)
                   :table (fn [generate depth]
                            (let [t {}]
                              (var k nil)
                              (for [_ 1 (math.random 16)]
                                (set k (generate depth))
                                ;; no nans plz
                                (while (not= k k) (set k (generate depth)))
                                (when (not= nil k)
                                  (tset t k (generate depth))))
                              t))
                   :sequence (fn [generate depth]
                               (let [t {}]
                                 (for [_ 1 (math.random 32)]
                                   (tset t (+ (length t) 1) (generate depth)))
                                 t))
                   :boolean (fn [] (> (math.random) 0.5))})

(local order [:number :string :table :sequence :boolean])

(fn generate [depth ?choice]
  "Generate a random piece of data."
  (if (< (+ 0.5 (/ (math.log depth 10) 1.2)) (math.random))
      (match (. generators (or (. order (or ?choice 1)) :boolean))
        generator (generator generate (+ depth 1)))
      (or (= nil ?choice) (<= ?choice (length order)))
      (generate depth (+ (or ?choice 1) 1))))

{: generate : generators : order}
