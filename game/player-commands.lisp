(in-package :io.github.thingywhat.trouble-behind)


;; Player location-oriented functions
(defun look ()
  "Outputs what the player sees around them."
  (append
   (car (get-node (actor-location *player*)))
   (describe-edges (get-edges (actor-location *player*)))
   (describe-items-at-location (get-item-details) (actor-location *player*))
   (describe-npcs-at-location (actor-location *player*))))

(defun look-at (item)
  "Gets the player to look at an item if they can see it."
  (if (can-see item (actor-location *player*))
      (car (get-item item))
      `(you cannot see any ,item around here.)))

(defun walk (direction)
  "Makes the player walk a specific direction if possible."
  (let ((edge (assoc direction (get-edges (actor-location *player*)))))
    (if edge
	(progn (setf (actor-location *player*) (cadr edge))
	       (look))
	`(i cannot see anywhere ,direction of here.))))

(defun inventory ()
  "Returns the player's inventory"
  (loop for item in (get-items)
     when (eq (item-location (car item)) 'inventory)
     collect (car item)))

(defun pickup (item)
  "Lets the player pick up an item and put it in their inventory."
  (if (can-see item (actor-location *player*))
      (if (member item (inventory))
	  '(you already have that.)
	  (let ((excuse (cadr (get-item item))))
	    (if (not excuse)
		(progn (push (cons item 'inventory) *item-locations*)
		       `(you pick up the ,item))
	        excuse)))
      `(you cannot see ,(a/an item) ,item from here.)))

(defun drop (item)
  "Lets the player drop an item at their current location"
  (if (member item (inventory))
      (progn (push (cons item (actor-location *player*)) *item-locations*)
	     `(you drop the ,item on the floor.))
      `(you dont have that.)))