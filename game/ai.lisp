(in-package :io.github.thingywhat.trouble-behind)

(let ((distance-hashes (make-hash-table)))
  (defun clear-distance-hashes ()
    "Clears the cache of distance-hashes"
    (setf distance-hashes (make-hash-table)))

  (defun make-distance-hash (start)
    "Creates a hash table that lists the shortest distance to each node
from the staring node passed in."
    (let ((visited (make-hash-table)))
      (labels ((neighbors (node)
                 (mapcar #'cadr (get-edges node)))
               (traverse (node depth)
                 (let ((current (gethash node visited)))
                   (unless (and current (< current depth))
                     (setf (gethash node visited) depth)
                     (mapc (lambda (node)
                             (traverse node (1+ depth)))
                           (neighbors node))))))
        (traverse start 0))
      visited)))

(defun get-nodes-within-range (node max-distance)
  "Returns an alist of the node names to distances within a set
distance from a given source node."
  (let ((hash (make-distance-hash node)))
    (loop for room being the hash-keys of hash
       for distance being the hash-values of hash
       when (>= max-distance distance) collect (cons room distance))))

(defun get-npcs-within-range (node max-distance)
  "Returns a list of NPCs within the specified distance of the
passed in node."
  (mapcan (lambda (node)
            (mapcan (lambda (npc)
                      (when (eq (car node) (actor-location npc))
                        (list npc)))
                    *npcs*))
          (get-nodes-within-range node max-distance)))

(let ((cache (make-hash-table :test #'equal)))
  (defun get-path (start end &optional retry)
    "Gets the shortest path from one node to another."
    (or (and (null retry) (gethash (cons start end) cache))
	(setf (gethash (cons start end) cache)
	      (loop with hash = (make-distance-hash end)
		 for distance from (or (gethash start hash) 0) downto 0
		 and node = start then
		   (cdr (assoc (1- distance)
			       (mapcar (lambda (node)
					 (cons (gethash (cadr node) hash)
					       (cadr node)))
				       (get-edges node)) :test #'equal))
		 collect node)))))

(defun update-random-path ()
  "Updates a random path so AIs can slowly \"learn\" new paths
  eventually if they are more efficeint than before."
  (flet ((random-node ()
	   (let ((nodes (mapcar #'car (get-nodes))))
	     (nth (random (length nodes)) nodes))))
    (get-path (random-node) (random-node) t)))


;; NPC command and AI implementation details
(defun npc-alert-players-in-range (npc)
  "Alerts the players of the sound of NPCs approaching them based on
the NPC's sounds alist."
  (let ((max-distance (reduce #'max (mapcar #'car (npc-sounds npc))))
        (location (actor-location npc)))
    (mapc (lambda (node)
            (when (eq (car node) (actor-location *player*))
              (princ-stylized-list (cdr (assoc (cdr node) (npc-sounds npc))))))
          (remove-if (lambda (node) (zerop (cdr node)))
                     (get-nodes-within-range location max-distance)))))

(defun display-walk (source npc)
  "Outputs what a player would see given their current location if an
NPC walked from some location to their current location."
  (flet ((get-direction (source destination)
	   (caar (remove-if-not (lambda (x) (eq destination (cadr x)))
				(get-edges source)))))
    (setf (npc-direction npc) nil)
    (let ((destination (actor-location npc)))
      (if (eq (actor-location *player*) source)
	  (unless (eq (actor-location *player*) destination)
	    (let ((direction (setf (npc-direction npc)
                                   (get-direction source destination))))
              (princ-stylized-list
	       `(you see ,(actor-name npc) walk to the ,direction))))
          (progn
            (unless (eq source destination)
              (npc-alert-players-in-range npc))
            (when (eq (actor-location *player*) destination)
              (let ((direction (setf (npc-direction npc)
                                     (get-direction destination source))))
                (princ-stylized-list
                 `(,(actor-name npc) enters from the ,direction)))))))))

(defgeneric npc-ai (npc motive)
  (:documentation "The AI that controls the passed in NPC each
  turn; Whis is done will do is based on its motive."))
(defgeneric npc-alert (npc location)
  (:documentation "How the AI reacts to being alerted of an event."))

(defun npc-follow-path (npc)
  "Gets an NPC to continue following the path it has."
  (let ((source (actor-location npc)))
    (setf (actor-location npc) (pop (npc-path npc)))
    (display-walk source npc)))

(defun npc-can-see-player (npc)
  "A function that determines if an NPC can see the player, based on
their location and hiding level."
  (let ((found (and (eq (actor-location npc) (actor-location *player*))
                    (< (player-hidden *player*) (random 10)))))
    (when found
      (setf (player-hidden *player*) 0))))

(defmethod npc-ai (npc motive)
  "The basic NPC AI, used when no matching AI is found for the
current motive:
This AI will make the NPC randomly move from one room to another every
once in a while... Or if a path is set, follow it."
  (let ((source (actor-location npc)))
    (if (npc-path npc)
        (npc-follow-path npc)
        (let ((neighbors (mapcar #'cadr (get-edges (actor-location npc)))))
          (when (and (zerop (random 3))
                     (not (zerop (length neighbors))))
            (setf (actor-location npc)
                  (nth (random (length neighbors)) neighbors)))
          (display-walk source npc)))))

(defmethod npc-ai (npc (motive (eql 'find-player)))
  "The NPC motive code for finding the player. (Currently in a dumb
and psychic way)"
  (if (and (npc-path npc)
           (not (eq (actor-location npc) (actor-location *player*))))
      (npc-follow-path npc)
      (progn
        (setf (npc-path npc)
              (if (eq (actor-location npc) (actor-location *player*))
                  (list (pick (mapcar #'cadr (get-edges (actor-location npc)))))
                  (cdr (get-path (actor-location npc) (actor-location *player*)))))
        (when (not (eq (actor-location npc) (actor-location *player*)))
          (npc-ai npc 'find-player))))
  (when (npc-can-see-player npc)
    (pop (npc-motives npc))))

(defmethod npc-ai (npc (motive (eql 'grab-player)))
  "The NPC motive code for when they wish to grab the player."
  (if (npc-can-see-player npc)
      (unless (or (zerop (random 2))
                  (eq (item-location 'player)
                      (actor-inventory npc)))
        (push (cons 'player (actor-inventory npc)) *item-locations*)
        (princ-stylized-list `(,(actor-name npc) grabs ahold of you!))
        (pop (npc-motives npc)))
      (progn (when (eq (actor-location npc) (actor-location *player*))
               (princ-stylized-list `(,(actor-name npc) starts looking around.)))
        (npc-ai npc (car (push 'find-player (npc-motives npc)))))))

(defmethod npc-ai (npc (motive (eql 'spank-player)))
  "The NPC motive code for angry NPCs that want to spank the player."
  (setf (npc-blocking npc) t)
  (if (eq (actor-inventory npc)
          (item-location 'player))
      (if (player-clothes *player*)
          (princ-stylized-list
           `(,(actor-name npc)
              removes your ,(car (push (pop (player-clothes *player*))
                                       (player-removed-clothes *player*)))))
          (progn (when (= (player-spunk *player*) 100)
                   (princ-stylized-list (pick (cadr (npc-begin-punishment-messages npc)))))
                 (princ-stylized-list (pick (cadr (npc-punishment-messages npc))))
                 (decf (player-spunk *player*) (1+ (random 10)))
                 (princ-stylized-list (get-player-spunk-message (player-spunk *player*)))))
      (npc-ai npc (car (push 'grab-player (npc-motives npc))))))

(defmethod npc-ai (npc (motive (eql 'dazed)))
  "The NPC motive when they get dazed"
  (when (eq (actor-location npc) (actor-location *player*))
    (princ-stylized-list `(,(actor-name npc) staggers!)))
  (pop (npc-motives npc)))

(defmethod npc-ai (npc (motive (eql 'investigate)))
  "Investigates the current location, or the location at the end of
their path."
  (flet ((investigate-event (event)
           (unless (find event (npc-seen npc) :test #'equal)
             (push event (npc-seen npc))
             (incf (npc-anger npc) (cadr (get-event-details event))))))
  (when (npc-path npc)
    (npc-follow-path npc))
  (mapc #'investigate-event (get-events-complete-at (actor-location npc)))))

(defun update-npcs ()
  "Updates all of the currently active NPCs after they completed their
tasks."
  (flet ((npc-ai-action (npc)
           (npc-ai npc (car (npc-motives npc)))))
    (mapc #'npc-ai-action *npcs*)))

(defun npc-alert-in-range (location distance)
  "Alerts any NPCs within a certain distance of some location of an
event happening"
  (mapc (lambda (npc) (npc-alert npc location))
        (get-npcs-within-range 'hallway distance)))

(defun npc-goto (npc location)
  "Tells an NPC they should go to a certain location."
  (setf (npc-path npc) (get-path (actor-location npc) location)))

(defmethod npc-alert ((npc npc) location)
  "Basic NPC alert AI... When alerted, the NPC goes to investigate the
node the event happened at."
  (npc-goto npc location))
