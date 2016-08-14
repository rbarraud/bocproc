(in-package :bocproc)

(defparameter *series-list* ()
  "List of series that are currently on the system.")

(defparameter *directory-list* ()
  "List of files currently in the base directory.")

;;; Basic objects and accessors
(defclass book-series ()
  ((series
    :type symbol
    :initarg :series
    :documentation "Series identifier. A keyword."
    :reader series)
   (specificities
    :initarg :specificities
    :documentation #.(concatenate 'string
                                  "An n×3 array"
                                  " with the names of the specificities"
                                  " and also their cutoffs. "
                                  " The rows are symbol, min, max.")
    :reader specificities)
   (format
    :initarg :format
    :documentation "The format of the filenames of this series."
    :reader book-format))
  (:documentation "Class for defining book series."))

(defmethod print-object ((object book-series) stream)
  (with-slots (series) object
    (print-unreadable-object (object stream :type t)
      (format stream "~a" series))))

(defclass book-page (book-series)
  ((page-numbers :initarg :page-numbers
                 :initform (vector)
                 :type (vector number)
                 :accessor page-numbers)
   (properties :initarg properties
               :initform (make-hash-table)
               :accessor properties))
  (:documentation "A manifestation of a book-series,
with a definite page number."))

(defmethod print-object ((object book-page) stream)
  (with-accessors ((properties properties)) object
    (print-unreadable-object (object stream :type t)
      (format stream "~a ~a" (series object) (page-numbers object))
      (loop for k being the hash-keys of properties
            for v being the hash-values of properties
            do (format stream " ~a ~a" k v)))))

(defgeneric get-page-property (object name)
  (:documentation "Retrieves the page property from a page object.")
  (:method ((object book-page) name)
    (gethash name (properties object))))

(defgeneric (setf get-page-property) (value object name)
  (:documentation "Sets the page property from a page object to VALUE.")
  (:method (value (object book-page) name)
    (setf (gethash name (properties object)) value)))

(defun define-book% (name format specificities)
  (push (make-instance
         'book-series
         :series name
         :format format
         :specificities
         (mapcar (lambda (list)
                   (loop repeat 3
                         for l = list then (cdr l)
                         collect (car l)))
                 specificities)) *series-list*))

(defmacro define-book (name specificities &body format)
  "Defines a book series."
  `(define-book% ',name ',format ',specificities))

(defun find-book (name)
  "Finds the book series named NAME from the list"
  (find name *series-list* :key #'series))

(defun undefine-book (name)
  "Removes the book series named NAME from the list."
  (delete name *series-list* :key #'series))

(defun make-page (name page-numbers)
  "Creates a page that is in the series NAME, with the specified PAGE-NUMBERS."
  (let ((found-page (if (symbolp name)
                        (find-book name)
                        name)))
    (make-instance
     'book-page
     :format (book-format found-page)
     :specificities (specificities found-page)
     :series (series found-page)
     :page-numbers (if (= (length page-numbers)
                          (length (specificities found-page)))
                       page-numbers
                       (error "Not enough page numbers for the book ~a"
                              (series found-page))))))

;;; Formatting books and their title.
(defun normalise-book-format (page fragment &key unknown-values limit)
  "Normalise and compute formatting options."
  (flet ((handle-missing-value ()
           (case unknown-values
             ((nil) (return-from normalise-book-format))
             (:glob (return-from normalise-book-format "*"))
             (:error (error
                      "Cannot compose file name, missing component ~a"
                      fragment)))))
    (etypecase fragment
      (string fragment)
      (character (string fragment))
      (symbol (normalise-book-format page (list fragment)
                                     :unknown-values unknown-values))
      (list
       (cond
         ((eql (car fragment) :date)
          (local-time:format-timestring nil (local-time:now)
                                        :format (cdr fragment)
                                        :timezone (get-timezone)))
         ((find (car fragment) (specificities page) :key #'first)
          (destructuring-bind (spec &key (pad 0) (type :number)) fragment
            (let* ((spec-pos (position spec (specificities page) :key #'first))
                   (page-number
                     (nth spec-pos (page-numbers page))))
              (when (or (not page-number)
                        (and limit
                             (< (position limit (specificities page)
                                          :key #'first)
                                spec-pos)))
                    (handle-missing-value))
              (case type
                (:letter
                 (format nil "~c" (number->letter page-number)))
                (:number
                 (format nil "~?"
                         (format nil "~~~d,'0d" pad)
                         (list page-number)))))))
         (t (let ((property-value (get-page-property page (car fragment))))
              (unless property-value
                (handle-missing-value))
              (format nil "~a" property-value))))))))

(defgeneric format-page (page &key unknown-values limit)
  (:documentation "Takes a PAGE and derives its filename from it.
If there are any parts that are not specified,
UNKNOWN-VALUES will control what happens next:

- NIL simply makes the function return nil.
- :ERROR causes an error to be raised.
- :GLOB, the default, replaces any unknown values with a globbing *.")
  (:method ((page book-page) &key (unknown-values :glob) limit)
    (apply #'concatenate 'string
           (namestring *books-location*)
           (loop for fragment in (book-format page)
                 if (normalise-book-format
                     page fragment :unknown-values unknown-values
                                   :limit limit) collect it
                 else do (return-from format-page)))))


(defun load-directory-contents ()
  (length
   (setf *directory-list*
         (directory (merge-pathnames
                     (make-pathname
                      :directory '(:relative :wild-inferiors)
                      :name :wild
                      :type :wild)
                     *books-location*)))))