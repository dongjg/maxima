;;; -*-  Mode: Lisp; Package: Maxima; Syntax: Common-Lisp; Base: 10 -*- ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     The data in this file contains enhancments.                    ;;;;;
;;;                                                                    ;;;;;
;;;  Copyright (c) 1984,1987 by William Schelter,University of Texas   ;;;;;
;;;     All rights reserved                                            ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;       1001 TRANSLATE properties for everyone.                        ;;;
;;;       (c) Copyright 1980 Massachusetts Institute of Technology       ;;;
;;;       Maintained by GJC                                              ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :maxima)

(macsyma-module trans4)

(transl-module trans4)

;;; These are translation properties for various operators.

(def%tr mnctimes (form)
  (setq form (tr-args (cdr form)))
  (cond ((= (length form) 2)
	 `($any ncmul2 . ,form))
	(t
	 `($any ncmuln (list . ,form) nil))))

(def%tr mncexpt (form)
  `($any . (ncpower ,@(tr-args (cdr form)))))

(def%tr $remainder (form)
  (let ((n (tr-nargs-check form '(2 . nil)))
	(tr-args (mapcar 'translate (cdr form))))
    (cond ((and (= n 2)
		(eq (caar tr-args) '$fixnum)
		(eq (car (cadr tr-args)) '$fixnum))
	   `($fixnum . (rem ,(cdr (car tr-args))
			,(cdr (cadr tr-args)))))
	  (t
	   (call-and-simp '$any '$remainder (mapcar 'cdr tr-args))))))

(def%tr $beta (form)
  `($any . (simplify (list '($beta) ,@(tr-args (cdr form))))))

(def%tr mfactorial (form)
  (setq form (translate (cadr form)))
  (cond ((eq (car form) '$fixnum)
	 `($number . (factorial ,(cdr form))))
	(t
	 `($any . (simplify  `((mfactorial) ,,(cdr form)))))))

;; Kill off the special code for translating sum and product.

(def%tr %sum $batcon)
(def%tr %product $batcon)


;; From MATCOM.
;; Temp autoloads needed for pdp-10. There is a better way
;; to distribute this info, too bad I never implemented it.

(mapc #'(lambda (x)
	  (let ((old-prop (get (cdr x) 'autoload)))
	    (if (not (null old-prop))
		(putprop (car x) old-prop 'autoload))))
      '((proc-$matchdeclare . $matchdeclare)
	(proc-$defmatch .     $defmatch)
	(proc-$defrule . $defrule)
	(proc-$tellsimpafter . $tellsimpafter)
	(proc-$tellsimp	 . $tellsimp	)))

(defun yuk-su-meta-prop (f form)
  (let ((meta-prop-p t)
	(meta-prop-l nil))
    (funcall f (cdr form))
    `($any . (progn ,@(mapcar #'patch-up-meval-in-fset (nreverse meta-prop-l))))))

(def%tr $matchdeclare (form)
  (do ((l (cdr form) (cddr l))
       (vars ()))
      ((null l)
       `($any . (progn 
		  ,@(mapcar #'(lambda (var)
				(dtranslate `(($define_variable)
					      ,var
					      ((mquote) ,var)
					      $any)))
			    vars)
		  ,(dtranslate `((sub_$matchdeclare) ,@(cdr form))))))
    (cond ((atom (car l))
	   (push (car l) vars))
	  ((eq (caaar l) 'mlist)
	   (setq vars (append (cdar l) vars))))))

(def%tr sub_$matchdeclare (form)
  (yuk-su-meta-prop 'proc-$matchdeclare `(($matchdeclare) ,@(cdr form))))

(def%tr $defmatch (form)
  (yuk-su-meta-prop 'proc-$defmatch form))

(def%tr $tellsimp (form)
  (yuk-su-meta-prop 'proc-$tellsimp form))

(def%tr $tellsimpafter (form)
  (yuk-su-meta-prop 'proc-$tellsimpafter form))

(def%tr $defrule (form)
  (yuk-su-meta-prop 'proc-$defrule form))

(defun patch-up-meval-in-fset (form)
  (cond ((not (eq (car form) 'fset))
	 form)
	
	(t
	 ;; FORM is always generated by META-FSET
	 (destructuring-let ((((nil ssymbol) (nil (nil definition) nil)) (cdr form)))
	   (unless (eq (car definition) 'lambda)
	     (tr-format
	      "PATCH-UP-MEVAL-IN-FSET: not a lambda expression: ~A~%"
	      definition)
	     (barfo))
	   (tr-format (intl:gettext "note: translating rule or match ~:M ...~%") ssymbol)
	   (setq definition (lisp->lisp-tr-lambda definition))
	   (if (null definition)
	       form
	       ;; If the definition is a lambda form, just use defun
	       ;; instead of fset.
	       (if (eq (car definition) 'lambda)
		   `(defun ,ssymbol ,@(cdr definition))
		   `(fset ',ssymbol ,definition)))))))

(defvar lisp->lisp-tr-lambda t)

(defun lisp->lisp-tr-lambda (l)
  ;; basically, a lisp->lisp translation, setting up
  ;; the proper lambda contexts for the special forms,
  ;; and calling TRANSLATE on the "lusers" generated by
  ;; Fateman braindamage, (MEVAL '$A), (MEVAL '(($F) $X)).
  (if lisp->lisp-tr-lambda
      (catch 'lisp->lisp-tr-lambda
	(tr-lisp->lisp l))
      ()))

(defun tr-lisp->lisp (exp)
  (if (atom exp)
      (cdr (translate-atom exp))
      (let ((op (car exp)))
	(if (symbolp op)
	    (funcall (or (get op 'tr-lisp->lisp) #'tr-lisp->lisp-default)
		     exp)
	    (progn (tr-format (intl:gettext "error: found a non-symbolic operator; I give up.~%"))
		   (throw 'lisp->lisp-tr-lambda ()))))))

(defun tr-lisp->lisp-default (exp)
  (cond ((macsyma-special-op-p (car exp))
	 (tr-format (intl:gettext "error: unhandled special operator ~:@M~%") (car exp))
	 (throw 'lisp->lisp-tr-lambda ()))
	('else
	 (tr-lisp->lisp-fun exp))))

(defun tr-lisp->lisp-fun (exp)
  (cons (car exp) (maptr-lisp->lisp (cdr exp))))

(defun maptr-lisp->lisp (l)
  (mapcar #'tr-lisp->lisp l))
(defun-prop (declare tr-lisp->lisp) (form)
  form)

(defun-prop (lambda tr-lisp->lisp) (form)
  (destructuring-let (((() arglist . body) form))
    (mapc #'tbind  arglist)
    (setq body (maptr-lisp->lisp body))
    `(lambda ,(tunbinds arglist) ,@body)))

(defun-prop (prog tr-lisp->lisp) (form)
  (destructuring-let (((() arglist . body) form))
    (mapc #'tbind arglist)
    (setq body (mapcar #'(lambda (x)
			   (if (atom x) x
			       (tr-lisp->lisp x)))
		       body))
    `(prog ,(tunbinds arglist) ,@body)))

;;(DEFUN RETLIST FEXPR (L)
;;  (CONS '(MLIST SIMP)
;;       (MAPCAR #'(LAMBDA (Z) (LIST '(MEQUAL SIMP) Z (MEVAL Z))) L)))

(defun-prop (retlist tr-lisp->lisp) (form)
  (push-autoload-def 'marrayref '(retlist_tr))
  `(retlist_tr ,@(mapcan #'(lambda (z)
			     (list `',z (tr-lisp->lisp z)))
			 (cdr form))))

(defun-prop (quote tr-lisp->lisp) (form) form)
(defprop catch tr-lisp->lisp-fun tr-lisp->lisp)
(defprop throw tr-lisp->lisp-fun tr-lisp->lisp)
(defprop return tr-lisp->lisp-fun tr-lisp->lisp)
(defprop function tr-lisp->lisp-fun tr-lisp->lisp)

(defun-prop (setq tr-lisp->lisp) (form)
  (do ((l (cdr form) (cddr l))
       (n ()))
      ((null l) (cons 'setq (nreverse n)))
    (push (car l) n)
    (push (tr-lisp->lisp (cadr l)) n)))

(defun-prop (msetq tr-lisp->lisp) (form)
  (cdr (translate `((msetq) ,@(cdr form)))))

(defun-prop (cond tr-lisp->lisp) (form)
  (cons 'cond (mapcar #'maptr-lisp->lisp (cdr form))))

(defprop not tr-lisp->lisp-fun tr-lisp->lisp)
(defprop and tr-lisp->lisp-fun tr-lisp->lisp)
(defprop or tr-lisp->lisp-fun tr-lisp->lisp)

(defvar unbound-meval-kludge-fix t)

(defun-prop (meval tr-lisp->lisp) (form)
  (setq form (cadr form))
  (cond ((and (not (atom form))
	      (eq (car form) 'quote))
	 (cdr (translate (cadr form))))
	(unbound-meval-kludge-fix
	 ;; only case of unbound MEVAL is in output of DEFMATCH,
	 ;; and appears like a useless double-evaluation of arguments.
	 form)
	('else
	 (tr-format (intl:gettext "error: found unbound MEVAL; I give up.~%"))
	 (throw 'lisp->lisp-tr-lambda ()))))

(defun-prop (is tr-lisp->lisp) (form)
  (setq form (cadr form))
  (cond ((and (not (atom form))
	      (eq (car form) 'quote))
	 (cdr (translate `(($is) ,(cadr form)))))
	('else
	 (tr-format (intl:gettext "error: found unbound IS; I give up.~%"))
	 (throw 'lisp->lisp-tr-lambda ()))))
