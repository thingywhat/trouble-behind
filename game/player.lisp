(in-package :io.github.thingywhat.trouble-behind)

(defun game-eval (&rest input)
  "Evaluates user input from (read) in a controlled manner and
performs the respective game commands passed in."
  (let* ((input (car input))
	 (command (car input)))
    (case command
      ((inventory i items)
       (or (inventory) '(nothing)))
      ((look inspect describe l)
       (if (cdr input)
           (look-at (cadr input))
           (look)))
      ((get pickup)
       (if (cdr input)
           (pickup (cadr input))
           '(pick up what?)))
      ((drop leave)
       (if (cdr input)
           (drop (cadr input))
           '(drop what?)))
      ((walk go run)
       (if (cdr input)
           (walk (cadr input))
           '(walk where?)))
      ((n e s w ne nw se sw)
       (game-eval (case command
                  (n '(north))
                  (e '(east))
                  (s '(south))
                  (w '(west))
                  (ne '(northeast))
                  (nw '(northwest))
                  (se '(southeast))
                  (sw '(southwest)))))
      (otherwise
       (cond
         ((member command
                  (append '(north east south west northeast northwest
                            southeast southwest)
                          (mapcar #'car
                                  (get-edges (actor-location *player*)))))
          (walk command))
         (t (special-command input)))))))

(defun handle-player (input)
  "Handles the actions a player can take in their given situation."
  (flet ((holding-player-p (npc)
           (eq (item-location 'player) (actor-inventory npc))))
    (let ((holding-npc (car (remove-if-not #'holding-player-p *npcs*))))
      (if (null holding-npc)
          (princ-stylized-list (game-eval (remove-if #'fluff-word-p input)))
          (if (eq (car input) 'struggle)
              (if (zerop (random 10))
                  (progn
                    (push (cons 'player 'free) *item-locations*)
                    (princ-stylized-list '(you get away!)))
                  (princ-stylized-list
                   '(you struggle... but it is fruitless.)))
              (princ-stylized-list
               `(you "can't" move! ,(actor-name holding-npc) is holding onto
                     you tightly! try to struggle to get away!)))))))

;; Main game loop
(defun game-loop ()
  "Loops through user input passing it to game-eval and stylyzing the
output."
  (loop for input = '(look)
     then (read-from-string (concatenate 'string "(" (read-line) ")"))
     when (or (eq (car input) 'quit)
              (and (<= (player-spunk *player*) 0)
                   (princ "You collapse into a sobbing heap. Game over!")))
     return t
     do (progn
          (handle-player input)
          (fresh-line)
          (update-npcs)
	  (fresh-line))))

(defun new-game ()
  "Starts a new game of trouble-behind"
  (reset-state)
  (game-loop))
